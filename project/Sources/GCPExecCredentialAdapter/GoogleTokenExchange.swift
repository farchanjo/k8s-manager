// GoogleTokenExchange.swift — GCPExecCredentialAdapter
// Exchanges a credential (refresh token or JWT assertion) for a Google OAuth2
// access token via URLSession. Returns the raw token string and expiry date.

import Foundation
import Logging

// MARK: - URLSessionProtocol

/// URLSession seam injected for testing. Production code uses `URLSession.shared`.
public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - GoogleTokenResponse

/// Successful response body from `https://oauth2.googleapis.com/token`.
struct GoogleTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int        // seconds from now
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - GoogleTokenError

/// Errors from the Google token exchange flow.
public enum GoogleTokenError: Error, Sendable {
    /// The token endpoint returned a non-200 HTTP status.
    case httpError(statusCode: Int, body: String)

    /// The response body could not be decoded as a token response.
    case decodingFailure(detail: String)

    /// URLSession threw an error (network, TLS, timeout, etc.).
    case networkFailure(detail: String)
}

// MARK: - GoogleTokenExchange

/// Calls the Google OAuth2 token endpoint and returns an access token.
public struct GoogleTokenExchange: Sendable {

    private static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let session: any URLSessionProtocol
    private let logger: Logger

    public init(
        session: any URLSessionProtocol = URLSession.shared,
        logger: Logger = Logger(label: "gcp.token-exchange")
    ) {
        self.session = session
        self.logger = logger
    }

    // MARK: - Public API

    /// Exchanges a refresh token for an access token.
    ///
    /// - Parameter adc: Parsed user credential fields.
    /// - Returns: `(accessToken, expiryDate)`.
    /// - Throws: `GoogleTokenError`.
    public func exchangeRefreshToken(adc: UserADC) async throws -> (token: String, expiry: Date) {
        var params: [String: String] = [
            "client_id": adc.clientID,
            "client_secret": adc.clientSecret,
            "refresh_token": adc.refreshToken,
            "grant_type": "refresh_token",
        ]
        logger.debug("Exchanging refresh token for client_id=\(adc.clientID)")
        return try await post(parameters: &params)
    }

    /// Exchanges a signed JWT assertion for an access token.
    ///
    /// - Parameters:
    ///   - assertion: Compact-serialised RS256 JWT.
    ///   - tokenURI: The `token_uri` from the service-account ADC (may differ
    ///     from the default endpoint for domain-wide delegation).
    /// - Returns: `(accessToken, expiryDate)`.
    /// - Throws: `GoogleTokenError`.
    public func exchangeJWTAssertion(
        assertion: String,
        tokenURI: String = "https://oauth2.googleapis.com/token"
    ) async throws -> (token: String, expiry: Date) {
        var params: [String: String] = [
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        ]
        logger.debug("Exchanging JWT assertion at \(tokenURI)")
        return try await post(parameters: &params, endpoint: tokenURI)
    }

    // MARK: - Private helpers

    private func post(
        parameters: inout [String: String],
        endpoint: String = tokenEndpoint
    ) async throws -> (token: String, expiry: Date) {
        guard let url = URL(string: endpoint) else {
            throw GoogleTokenError.networkFailure(detail: "Invalid token endpoint URL: \(endpoint)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode(parameters)

        let (data, response) = try await withNetworkErrorMapping {
            try await self.session.data(for: request)
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(decoding: data, as: UTF8.self)
            throw GoogleTokenError.httpError(statusCode: http.statusCode, body: body)
        }

        let decoded: GoogleTokenResponse
        do {
            decoded = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        } catch {
            throw GoogleTokenError.decodingFailure(detail: error.localizedDescription)
        }

        let expiry = Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        logger.debug("Received access_token, expires_in=\(decoded.expiresIn)s")
        return (decoded.accessToken, expiry)
    }

    private func formEncode(_ params: [String: String]) -> Data {
        params
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }
}

// MARK: - Network error mapping

private func withNetworkErrorMapping<T: Sendable>(
    _ block: () async throws -> T
) async throws -> T {
    do {
        return try await block()
    } catch let error as GoogleTokenError {
        throw error
    } catch {
        throw GoogleTokenError.networkFailure(detail: error.localizedDescription)
    }
}
