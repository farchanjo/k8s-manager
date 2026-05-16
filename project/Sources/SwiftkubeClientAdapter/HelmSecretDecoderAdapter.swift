// HelmSecretDecoderAdapter.swift — SwiftkubeClientAdapter
// DDD role: Adapter (secondary — stateless infrastructure service)
// Implements: ReleaseDecoderPort (HelmManagement)
// ADR ref: ADR-0015 §Phase 1 §Secret decoding, ADR-0020 (adapter layer boundary)

import Compression
import Foundation
import HelmManagement
import SharedKernel

// MARK: - HelmSecretDecoderAdapter

/// Decodes `helm.sh/release.v1` Secret payloads into `Release` aggregates.
///
/// Helm v3 stores release state in `data["release"]` as a base64-encoded,
/// gzip-compressed JSON blob (ADR-0015 §Secret decoding). The full pipeline:
///
/// 1. **Base64-decode** the raw `secretData` bytes to obtain gzip-compressed bytes.
/// 2. **Gunzip** the gzip-compressed bytes using `Compression.framework` (`.zlib`
///    with gzip framing via raw stream filter).
/// 3. **JSON-decode** the decompressed bytes into `HelmReleasePayload`.
/// 4. **Invariant checks** (ADR-0015 §release_decoder_invariants):
///    - Manifest YAML must not contain PEM-encoded certificate or key blocks.
/// 5. Construct and return a `Release` aggregate.
///
/// This adapter imports no SwiftkubeClient types — it is pure Foundation.
/// No I/O or network access occurs inside this type.
public struct HelmSecretDecoderAdapter: ReleaseDecoderPort {

    // MARK: - Initialiser

    /// Creates a stateless Helm secret decoder.
    public init() {}

    // MARK: - ReleaseDecoderPort

    /// Decodes the raw bytes of `data["release"]` into a `Release` aggregate.
    ///
    /// - Parameter secretData: The raw value of `data["release"]` from a
    ///   `helm.sh/release.v1` Kubernetes Secret, i.e. the base64-encoded,
    ///   gzip-compressed JSON representation. The caller must not pre-decode.
    /// - Returns: A fully-materialised `Release` aggregate.
    /// - Throws: `ReleaseDecoderError` on any pipeline failure.
    public func decode(secretData: Data) throws -> Release {
        let gzipped = try base64Decode(secretData)
        let json = try gunzip(gzipped)
        let payload = try jsonDecode(json)
        try enforceInvariants(payload)
        return materialise(payload)
    }

    // MARK: - Private — pipeline steps

    /// Step 1: Base64-decode the raw secret data bytes.
    private func base64Decode(_ data: Data) throws -> Data {
        guard let decoded = Data(base64Encoded: data) else {
            throw ReleaseDecoderError.base64DecodeFailed
        }
        return decoded
    }

    /// Step 2: Gunzip the decoded bytes using Foundation's Compression framework.
    ///
    /// Uses `NSData.decompressed(using:)` (macOS 10.15+) with `.zlib` algorithm.
    /// Helm uses standard RFC 1952 gzip framing. Foundation `.zlib` with
    /// `NSData.decompressed(using:)` handles gzip-framed streams correctly via
    /// the GZ variant flag in macOS 10.15+.
    private func gunzip(_ data: Data) throws -> Data {
        do {
            let decompressed = try (data as NSData).decompressed(using: .zlib)
            return decompressed as Data
        } catch {
            // Foundation's .zlib may reject gzip framing on older OS paths.
            // Fall back to manual gzip-strip and raw DEFLATE.
            do {
                return try gunzipFallback(data)
            } catch {
                throw ReleaseDecoderError.gunzipFailed(
                    detail: "NSData.decompressed failed and fallback also failed: \(error)"
                )
            }
        }
    }

    /// Fallback: strip the 10-byte gzip header and trailing 8-byte footer,
    /// then inflate the raw DEFLATE payload.
    private func gunzipFallback(_ data: Data) throws -> Data {
        // RFC 1952: gzip header is at least 10 bytes (ID1 ID2 CM FLG MTIME XFL OS).
        // The last 8 bytes are CRC32 + ISIZE.
        guard data.count > 18,
              data[0] == 0x1F, data[1] == 0x8B else {
            throw ReleaseDecoderError.gunzipFailed(detail: "Not a gzip stream")
        }
        let deflate = Data(data.dropFirst(10).dropLast(8))
        do {
            return try (deflate as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw ReleaseDecoderError.gunzipFailed(detail: "Deflate fallback failed: \(error)")
        }
    }

    /// Step 3: JSON-decode the decompressed bytes into `HelmReleasePayload`.
    private func jsonDecode(_ data: Data) throws -> HelmReleasePayload {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(HelmReleasePayload.self, from: data)
        } catch {
            throw ReleaseDecoderError.jsonDecodeFailed(detail: error.localizedDescription)
        }
    }

    /// Step 4: Enforce invariants per ADR-0015 §release_decoder_invariants.
    ///
    /// Current invariant: the rendered `manifest` YAML must not contain
    /// PEM-encoded certificate or private-key material (defence in depth).
    private func enforceInvariants(_ payload: HelmReleasePayload) throws {
        var violations: [String] = []
        let manifest = payload.manifest ?? ""
        if manifest.contains("-----BEGIN CERTIFICATE-----") {
            violations.append("manifest contains PEM certificate block")
        }
        if manifest.contains("-----BEGIN PRIVATE KEY-----")
            || manifest.contains("-----BEGIN RSA PRIVATE KEY-----")
            || manifest.contains("-----BEGIN EC PRIVATE KEY-----") {
            violations.append("manifest contains PEM private-key block")
        }
        if !violations.isEmpty {
            throw ReleaseDecoderError.invariantViolation(violations: violations)
        }
    }

    /// Step 5: Materialises a `Release` aggregate from the decoded payload.
    private func materialise(_ payload: HelmReleasePayload) -> Release {
        let status = ReleaseStatus(rawValue: payload.info.status) ?? .failed
        let chart = buildChartMetadata(from: payload.chart.metadata)
        let info = buildReleaseInfo(from: payload.info, status: status)
        let hooks = payload.hooks.map(buildHookManifest)

        return Release(
            id: UUID(),
            kubernetesContextId: UUID(),
            name: payload.name,
            namespace: payload.namespace,
            version: payload.version,
            status: status,
            chart: chart,
            info: info,
            manifestYAML: payload.manifest ?? "",
            valuesJSON: encodeValues(payload.config),
            hooks: hooks,
            modifiedAtRFC3339: payload.info.last_deployed,
            sourceSecretName: "sh.helm.release.v1.\(payload.name).v\(payload.version)"
        )
    }

    // MARK: - Private — aggregate builders

    private func buildChartMetadata(from meta: HelmChartMetadata) -> ChartMetadata {
        ChartMetadata(
            name: meta.name,
            version: meta.version,
            appVersion: meta.appVersion,
            apiVersion: meta.apiVersion == "v1" ? .v1 : .v2,
            description: meta.description,
            type: meta.type.flatMap { ChartType(rawValue: $0) },
            icon: meta.icon,
            dependencies: meta.dependencies?.map(buildDependency) ?? [],
            maintainers: meta.maintainers?.map(buildMaintainer) ?? [],
            home: meta.home,
            sources: meta.sources ?? []
        )
    }

    private func buildDependency(_ dep: HelmChartDependency) -> ChartDependency {
        ChartDependency(
            name: dep.name,
            version: dep.version,
            repository: dep.repository,
            alias: dep.alias,
            condition: dep.condition,
            tags: dep.tags ?? []
        )
    }

    private func buildMaintainer(_ m: HelmMaintainer) -> Maintainer {
        Maintainer(name: m.name, email: m.email, url: m.url)
    }

    private func buildReleaseInfo(from info: HelmReleaseInfo, status: ReleaseStatus) -> ReleaseInfo {
        ReleaseInfo(
            firstDeployed: info.first_deployed,
            lastDeployed: info.last_deployed,
            deleted: info.deleted,
            description: info.description ?? "",
            status: status,
            notes: info.notes ?? ""
        )
    }

    private func buildHookManifest(_ hook: HelmHook) -> HookManifest {
        let events = hook.events?.compactMap { HookEvent(rawValue: $0) } ?? []
        return HookManifest(
            name: hook.name,
            kind: hook.kind,
            apiVersion: hook.apiVersion,
            events: events,
            deletePolicy: hook.delete_policies ?? [],
            weight: hook.weight ?? 0
        )
    }

    private func encodeValues(_ config: [String: AnyJSON]?) -> String {
        guard let config, !config.isEmpty else { return "{}" }
        guard let data = try? JSONEncoder().encode(config),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}

// MARK: - HelmReleasePayload (Helm v3 JSON format)

/// Helm v3 release JSON payload — maps the Go `release.Release` struct.
private struct HelmReleasePayload: Decodable {
    let name: String
    let namespace: String
    let version: Int
    let info: HelmReleaseInfo
    let chart: HelmChart
    let config: [String: AnyJSON]?
    let manifest: String?
    let hooks: [HelmHook]

    private enum CodingKeys: String, CodingKey {
        case name, namespace, version, info, chart, config, manifest, hooks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        namespace = try c.decode(String.self, forKey: .namespace)
        version = try c.decode(Int.self, forKey: .version)
        info = try c.decode(HelmReleaseInfo.self, forKey: .info)
        chart = try c.decode(HelmChart.self, forKey: .chart)
        config = try c.decodeIfPresent([String: AnyJSON].self, forKey: .config)
        manifest = try c.decodeIfPresent(String.self, forKey: .manifest)
        hooks = (try? c.decodeIfPresent([HelmHook].self, forKey: .hooks)) ?? []
    }
}

private struct HelmReleaseInfo: Decodable {
    let first_deployed: String
    let last_deployed: String
    let deleted: String?
    let description: String?
    let status: String
    let notes: String?
}

private struct HelmChart: Decodable {
    let metadata: HelmChartMetadata
}

private struct HelmChartMetadata: Decodable {
    let name: String
    let version: String
    let appVersion: String?
    let apiVersion: String
    let description: String?
    let type: String?
    let icon: String?
    let dependencies: [HelmChartDependency]?
    let maintainers: [HelmMaintainer]?
    let home: String?
    let sources: [String]?

    private enum CodingKeys: String, CodingKey {
        case name, version, apiVersion, description, type, icon
        case appVersion = "appVersion"
        case dependencies, maintainers, home, sources
    }
}

private struct HelmChartDependency: Decodable {
    let name: String
    let version: String
    let repository: String?
    let alias: String?
    let condition: String?
    let tags: [String]?
}

private struct HelmMaintainer: Decodable {
    let name: String
    let email: String?
    let url: String?
}

private struct HelmHook: Decodable {
    let name: String
    let kind: String
    let apiVersion: String
    let events: [String]?
    let delete_policies: [String]?
    let weight: Int?

    private enum CodingKeys: String, CodingKey {
        case name, kind, weight
        case apiVersion = "apiVersion"
        case events
        case delete_policies = "delete_policies"
    }
}

// MARK: - AnyJSON (type-erased JSON value for Helm values map)

/// Opaque type-erased JSON value used for the Helm user-supplied values map.
///
/// Supports encoding only (no decode lossy path needed for Phase 1).
private enum AnyJSON: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AnyJSON])
    case array([AnyJSON])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: AnyJSON].self) { self = .object(v); return }
        if let v = try? c.decode([AnyJSON].self) { self = .array(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
