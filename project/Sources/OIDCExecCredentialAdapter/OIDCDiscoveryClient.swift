// OIDCDiscoveryClient.swift — OIDCExecCredentialAdapter
// DDD role: Infrastructure — OIDC discovery + JWKS fetch via URLSession
// ADR-0018 §OIDC generic authentication protocol

import Foundation
import Logging

// MARK: - OIDCDiscoveryDocument

/// Parsed subset of the OpenID Connect Discovery document
/// (`<issuer>/.well-known/openid-configuration`).
///
/// Only the fields required by the OIDC exec-credential flow are modelled;
/// extra provider-specific fields are ignored.
public struct OIDCDiscoveryDocument: Decodable, Sendable {

    /// The issuer URL used to validate the `iss` claim in id-tokens.
    public let issuer: String

    /// The authorization endpoint URL (used for the interactive PKCE flow).
    public let authorizationEndpoint: String

    /// The token endpoint URL (used for code exchange and refresh-token grants).
    public let tokenEndpoint: String

    /// The JWKS URI from which public keys are fetched for id-token verification.
    public let jwksUri: String

    private enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case jwksUri = "jwks_uri"
    }
}

// MARK: - OIDCDiscoveryError

/// Errors produced by ``OIDCDiscoveryClient``.
public enum OIDCDiscoveryError: Error, Sendable {

    /// The discovery URL did not return an HTTP 200 response.
    case httpError(statusCode: Int)

    /// The response body could not be parsed as a discovery document.
    case parseError(detail: String)

    /// The JWKS URI returned in the discovery document is not a valid URL.
    case invalidJwksURI(raw: String)
}

// MARK: - OIDCDiscoveryClient

/// Fetches the OpenID Connect discovery document and JWKS for a given issuer.
///
/// All network calls use a caller-supplied `URLSession` so that custom CA
/// bundles required by private Kubernetes clusters (ADR-0018 §CA bundle) can
/// be injected without modifying system-wide TLS trust.
public struct OIDCDiscoveryClient: Sendable {

    private let session: URLSession
    private let logger: Logger

    /// Creates a new discovery client.
    ///
    /// - Parameters:
    ///   - session: The `URLSession` to use for all network calls. Pass a
    ///     session configured with a custom delegate to pin to a private CA.
    ///   - logger: Logger label for structured output.
    public init(session: URLSession = .shared, logger: Logger) {
        self.session = session
        self.logger = logger
    }

    // MARK: Discovery fetch

    /// Fetches `<issuer>/.well-known/openid-configuration` and returns the
    /// parsed discovery document.
    ///
    /// - Parameter issuerURL: The issuer base URL (no trailing slash required).
    /// - Throws: ``OIDCDiscoveryError``
    public func fetchDiscovery(issuerURL: URL) async throws -> OIDCDiscoveryDocument {
        let discoveryURL = issuerURL
            .appendingPathComponent(".well-known")
            .appendingPathComponent("openid-configuration")
        logger.debug("Fetching OIDC discovery document", metadata: ["url": "\(discoveryURL)"])

        let (data, response) = try await session.data(from: discoveryURL)
        try assertHTTP200(response: response)

        do {
            return try JSONDecoder().decode(OIDCDiscoveryDocument.self, from: data)
        } catch {
            throw OIDCDiscoveryError.parseError(detail: error.localizedDescription)
        }
    }

    // MARK: JWKS fetch

    /// Fetches the JSON Web Key Set from the URI advertised in the discovery document.
    ///
    /// - Parameter jwksURI: The raw string from `OIDCDiscoveryDocument.jwksUri`.
    /// - Throws: ``OIDCDiscoveryError``
    public func fetchJWKS(jwksURI: String) async throws -> Data {
        guard let url = URL(string: jwksURI) else {
            throw OIDCDiscoveryError.invalidJwksURI(raw: jwksURI)
        }
        logger.debug("Fetching JWKS", metadata: ["url": "\(url)"])
        let (data, response) = try await session.data(from: url)
        try assertHTTP200(response: response)
        return data
    }

    // MARK: Private helpers

    private func assertHTTP200(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode == 200 else {
            throw OIDCDiscoveryError.httpError(statusCode: http.statusCode)
        }
    }
}
