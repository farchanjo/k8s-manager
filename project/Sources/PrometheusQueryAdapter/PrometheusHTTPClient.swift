// PrometheusHTTPClient.swift — infrastructure adapter
// Implements: PrometheusQueryPort from MetricsObservability
// ADR ref: ADR-0016 (HTTP client strategy, 30s timeout, downsampling)
// ADR ref: ADR-0044 (PromQL injection prevention — label-value allowlist)

import AsyncHTTPClient
import Foundation
import Logging
import MetricsObservability

// MARK: - Base64 helper (no Foundation.Data.base64EncodedString import needed)

private extension String {
    /// Encodes the UTF-8 representation of `self` as Base64.
    var base64Encoded: String {
        Data(utf8).base64EncodedString()
    }
}

// MARK: - PrometheusHTTPClient

/// Executes PromQL instant and range queries against a Prometheus HTTP API.
///
/// Conforms to `PrometheusQueryPort`. Uses `AsyncHTTPClient` as the transport
/// layer (Tier-A dependency per ADR-0019). Every request carries a 30-second
/// timeout (ADR-0016). Label values are validated against the ADR-0044
/// allowlist before URL composition.
public struct PrometheusHTTPClient: PrometheusQueryPort {

    // MARK: Private state

    private let httpClient: HTTPClient
    private let logger: Logger

    // MARK: Init

    /// Creates a new `PrometheusHTTPClient`.
    ///
    /// - Parameters:
    ///   - httpClient: Shared `AsyncHTTPClient` instance. Caller owns lifecycle.
    ///   - logger: Logger for request/error events.
    public init(
        httpClient: HTTPClient,
        logger: Logger = Logger(label: "PrometheusHTTPClient")
    ) {
        self.httpClient = httpClient
        self.logger = logger
    }

    // MARK: PrometheusQueryPort

    /// Executes a PromQL instant query (`/api/v1/query`).
    public func instantQuery(
        _ query: PromQuery,
        endpoint: PrometheusEndpoint
    ) async throws -> PromQueryResult {
        try validateLabelValues(query)
        let url = try instantURL(for: query, base: endpoint.url)
        let request = buildRequest(url: url, endpoint: endpoint)
        let bytes = try await execute(request)
        return try decodeVector(bytes)
    }

    /// Executes a PromQL range query (`/api/v1/query_range`).
    ///
    /// Results are downsampled to <= 200 points per ADR-0016.
    public func rangeQuery(
        _ query: PromQuery,
        endpoint: PrometheusEndpoint
    ) async throws -> PromQueryResult {
        try validateLabelValues(query)
        let url = try rangeURL(for: query, base: endpoint.url)
        let request = buildRequest(url: url, endpoint: endpoint)
        let bytes = try await execute(request)
        return try decodeMatrix(bytes)
    }
}

// MARK: - ADR-0044 label-value guard

private extension PrometheusHTTPClient {

    /// Validates every value in `query.labelSelector` against the ADR-0044
    /// allowlist (`^[a-zA-Z0-9._-]{1,63}$`).
    /// Throws `PrometheusQueryError.invalidParameter` on the first violation.
    func validateLabelValues(_ query: PromQuery) throws {
        guard let selectors = query.labelSelector else { return }
        for (key, value) in selectors {
            guard isAllowedLabelValue(value) else {
                throw PrometheusQueryError.invalidParameter(
                    value: value,
                    template: key
                )
            }
        }
    }

    /// Returns `true` when `value` satisfies the ADR-0044 allowlist.
    ///
    /// Pattern: `^[a-zA-Z0-9._-]{1,63}$`
    /// Evaluated inline to avoid a non-`Sendable` `Regex` static property.
    func isAllowedLabelValue(_ value: String) -> Bool {
        let len = value.count
        guard len >= 1, len <= 63 else { return false }
        return value.allSatisfy { char in
            char.isLetter || char.isNumber
                || char == "." || char == "_" || char == "-"
        }
    }
}

// MARK: - URL builders

private extension PrometheusHTTPClient {

    func instantURL(for query: PromQuery, base: String) throws -> String {
        guard var components = URLComponents(string: base + "/api/v1/query") else {
            throw PrometheusQueryError.transportError(detail: "Invalid base URL: \(base)")
        }
        let now = ISO8601DateFormatter().string(from: Date())
        components.queryItems = [
            URLQueryItem(name: "query", value: query.expr),
            URLQueryItem(name: "time", value: now),
        ]
        guard let url = components.url?.absoluteString else {
            throw PrometheusQueryError.transportError(detail: "Could not compose instant URL")
        }
        return url
    }

    func rangeURL(for query: PromQuery, base: String) throws -> String {
        guard let range = query.range else {
            throw PrometheusQueryError.transportError(detail: "rangeQuery called with instant PromQuery")
        }
        guard var components = URLComponents(string: base + "/api/v1/query_range") else {
            throw PrometheusQueryError.transportError(detail: "Invalid base URL: \(base)")
        }
        components.queryItems = [
            URLQueryItem(name: "query", value: query.expr),
            URLQueryItem(name: "start", value: range.start),
            URLQueryItem(name: "end", value: range.end),
            URLQueryItem(name: "step", value: "\(range.stepSeconds)"),
        ]
        guard let url = components.url?.absoluteString else {
            throw PrometheusQueryError.transportError(detail: "Could not compose range URL")
        }
        return url
    }
}

// MARK: - Request builder

// `buildRequest` is `internal` (not `private`) so that `@testable import`
// can expose it for isolated header-injection tests (AuthStrategyTests).
extension PrometheusHTTPClient {

    /// Constructs an `HTTPClientRequest` for `url`, applying the authentication
    /// strategy declared on `endpoint`.
    ///
    /// - `.none`: No `Authorization` header.
    /// - `.bearerInherit`: No header added here; session boundary injects it.
    /// - `.bearer(token:)`: Emits `Authorization: Bearer <token>`.
    /// - `.basic(username:password:)`: Emits `Authorization: Basic <b64>`.
    func buildRequest(url: String, endpoint: PrometheusEndpoint) -> HTTPClientRequest {
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "Accept", value: "application/json")
        switch endpoint.authStrategy {
        case .none:
            break
        case .bearerInherit:
            // Token injection for bearerInherit is performed at the session
            // boundary (outside this adapter). No header added here.
            break
        case .bearer(let token):
            request.headers.add(name: "Authorization", value: "Bearer \(token)")
        case .basic(let username, let password):
            let credentials = "\(username):\(password)".base64Encoded
            request.headers.add(name: "Authorization", value: "Basic \(credentials)")
        }
        return request
    }
}

// MARK: - Request executor

private extension PrometheusHTTPClient {

    func execute(_ request: HTTPClientRequest) async throws -> Data {
        let response: HTTPClientResponse
        do {
            response = try await httpClient.execute(request, timeout: .seconds(30))
        } catch {
            throw PrometheusQueryError.transportError(detail: error.localizedDescription)
        }
        if response.status == .unauthorized {
            throw PrometheusQueryError.unauthorized
        }
        let statusCode = Int(response.status.code)
        if statusCode >= 500 {
            throw PrometheusQueryError.transportError(detail: "Server error HTTP \(statusCode)")
        }
        guard statusCode == 200 else {
            throw PrometheusQueryError.unexpectedStatus(code: statusCode, detail: "HTTP \(statusCode)")
        }
        let collected = try await response.body.collect(upTo: 32 * 1024 * 1024)
        return Data(collected.readableBytesView)
    }
}

// MARK: - JSON decoding

private extension PrometheusHTTPClient {

    func decodeVector(_ data: Data) throws -> PromQueryResult {
        let envelope = try decode(PromEnvelope.self, from: data)
        guard envelope.data.resultType == "vector" else {
            throw PrometheusQueryError.unsupportedResultType(envelope.data.resultType)
        }
        let samples = try envelope.data.result.map { item in
            try MetricSample(
                metric: item.metric,
                timestampUnix: item.valueTimestamp(),
                value: item.valueDouble()
            )
        }
        return .instantVector(samples)
    }

    func decodeMatrix(_ data: Data) throws -> PromQueryResult {
        let envelope = try decode(PromEnvelope.self, from: data)
        guard envelope.data.resultType == "matrix" else {
            throw PrometheusQueryError.unsupportedResultType(envelope.data.resultType)
        }
        let series = try envelope.data.result.map { item -> TimeSeries in
            let points = try item.valuesPoints()
            return TimeSeries(metric: item.metric, points: points).downsampled()
        }
        return .rangeMatrix(series)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PrometheusQueryError.decodeError(detail: error.localizedDescription)
        }
    }
}

// MARK: - Wire types

/// Top-level Prometheus API response envelope.
private struct PromEnvelope: Decodable {
    let status: String
    let data: PromData
}

/// `data` field of the Prometheus API response.
private struct PromData: Decodable {
    let resultType: String
    let result: [PromResultItem]

    enum CodingKeys: String, CodingKey {
        case resultType
        case result
    }
}

/// One item in `data.result` — covers both vector and matrix shapes.
///
/// Vector items carry a single `value` tuple `[timestamp, valueString]`.
/// Matrix items carry a `values` array of such tuples.
private struct PromResultItem: Decodable {
    let metric: [String: String]
    /// Single-sample tuple for vector results (`[timestamp, "value"]`).
    let value: [PromScalar]?
    /// Multi-sample array for matrix results.
    let values: [[PromScalar]]?

    /// Extracts the Unix timestamp from a vector `value` pair.
    func valueTimestamp() throws -> Double {
        guard let pair = value, pair.count == 2 else {
            throw PrometheusQueryError.decodeError(detail: "Missing vector value pair")
        }
        return pair[0].asDouble
    }

    /// Extracts the numeric value from a vector `value` pair.
    func valueDouble() throws -> Double {
        guard let pair = value, pair.count == 2 else {
            throw PrometheusQueryError.decodeError(detail: "Missing vector value pair")
        }
        guard let v = pair[1].stringValue.flatMap(Double.init) else {
            throw PrometheusQueryError.decodeError(
                detail: "Non-numeric value: \(pair[1].stringValue ?? "?")"
            )
        }
        return v
    }

    /// Converts matrix `values` tuples to `DataPoint` array.
    func valuesPoints() throws -> [DataPoint] {
        guard let rows = values else {
            throw PrometheusQueryError.decodeError(detail: "Missing matrix values array")
        }
        return try rows.map { row in
            guard row.count == 2 else {
                throw PrometheusQueryError.decodeError(
                    detail: "Matrix row must have 2 elements, got \(row.count)"
                )
            }
            guard let v = row[1].stringValue.flatMap(Double.init) else {
                throw PrometheusQueryError.decodeError(detail: "Non-numeric matrix value")
            }
            return DataPoint(tUnix: row[0].asDouble, value: v)
        }
    }
}

// MARK: - PromScalar

/// Minimal polymorphic `Codable` wrapper for Prometheus `[timestamp, "value"]` tuples.
///
/// Prometheus encodes timestamps as JSON numbers and values as JSON strings
/// in the same array position. This type handles both without a third-party
/// `AnyCodable` library.
private struct PromScalar: Decodable {
    private enum Raw {
        case number(Double)
        case text(String)
    }

    private let raw: Raw

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            raw = .number(d)
        } else if let s = try? container.decode(String.self) {
            raw = .text(s)
        } else {
            raw = .text("")
        }
    }

    /// Returns the value as a `Double`. String values are parsed numerically.
    var asDouble: Double {
        switch raw {
        case .number(let d): return d
        case .text(let s): return Double(s) ?? 0
        }
    }

    /// Returns the string representation, or `nil` for pure numeric tokens.
    var stringValue: String? {
        guard case .text(let s) = raw else { return nil }
        return s
    }
}
