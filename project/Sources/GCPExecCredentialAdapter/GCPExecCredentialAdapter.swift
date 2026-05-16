// GCPExecCredentialAdapter.swift — infrastructure adapter
// Implements ExecPluginPort for GKE clusters using Application Default
// Credentials (ADC). Replaces the defunct google-auth-library-swift per
// ADR-0018 (GCP credential resolution, in-house, 2026-05-15).
//
// Supported ADC types:
//   - authorized_user  → refresh-token grant → access token
//   - service_account  → RS256 JWT assertion → access token
//   - external_account → DEFERRED (returns ExecPluginError.unimplemented)

import Foundation
import JWTKit
import Crypto
import _CryptoExtras
import ClusterConnectivity
import SharedKernel
import Logging

// MARK: - GCPExecCredentialAdapter

/// `ExecPluginPort` implementation for GKE clusters.
///
/// Reads Application Default Credentials from disk, exchanges them for a
/// short-lived Google OAuth2 access token, and returns the token as a
/// Kubernetes `ExecCredential` (client.authentication.k8s.io/v1) bearer token.
///
/// The adapter is `Sendable` and `struct`-based: all mutable state lives in
/// injected helpers that are themselves `Sendable`.
public struct GCPExecCredentialAdapter: ExecPluginPort, Sendable {

    // Internal visibility allows @testable access in the test-target extension
    // while keeping these fields out of the public API surface.
    let loader: ADCLoader
    let signer: ServiceAccountJWTSigner
    let exchange: GoogleTokenExchange
    private let logger: Logger

    // MARK: - Initialiser

    /// Creates an adapter with injectable dependencies for testing.
    ///
    /// - Parameters:
    ///   - loader: ADC file reader. Defaults to `ADCLoader()`.
    ///   - signer: RS256 JWT signer. Defaults to `ServiceAccountJWTSigner()`.
    ///   - exchange: OAuth2 token exchange. Defaults to `GoogleTokenExchange()`.
    ///   - logger: Swift-log logger. Defaults to the `gcp.exec-credential` label.
    public init(
        loader: ADCLoader = ADCLoader(),
        signer: ServiceAccountJWTSigner = ServiceAccountJWTSigner(),
        exchange: GoogleTokenExchange = GoogleTokenExchange(),
        logger: Logger = Logger(label: "gcp.exec-credential")
    ) {
        self.loader = loader
        self.signer = signer
        self.exchange = exchange
        self.logger = logger
    }

    // MARK: - ExecPluginPort

    /// Resolves GCP credentials and returns an `AuthInfo` containing the
    /// access token formatted as a Kubernetes `ExecCredential` bearer token.
    ///
    /// - Parameter auth: The exec-plugin invocation parameters parsed from the
    ///   kubeconfig. Only the `apiVersion` field is inspected; other fields are
    ///   ignored for the GCP adapter.
    /// - Returns: `AuthInfo.bearerToken` whose token is a raw Google OAuth2
    ///   access token (a Google-issued opaque string accepted by the GKE
    ///   token-review webhook).
    /// - Throws: `ExecPluginError.unimplemented` for external-account ADC.
    ///   `ExecPluginError.parseError` when ADC cannot be loaded or parsed.
    public func resolve(auth: ExecPluginAuth) async throws -> AuthInfo {
        logger.info("GCPExecCredentialAdapter resolving credentials", metadata: [
            "command": .string(auth.command),
            "apiVersion": .string(auth.apiVersion),
        ])

        let credential: ADCCredential
        do {
            credential = try await loader.load()
        } catch let error as ADCLoaderError {
            throw ExecPluginError.parseError(detail: "ADC load failed: \(error)")
        } catch {
            throw ExecPluginError.parseError(detail: error.localizedDescription)
        }

        switch credential {
        case .userCredentials(let userADC):
            return try await resolveUserCredentials(userADC)
        case .serviceAccount(let saADC):
            return try await resolveServiceAccount(saADC)
        case .externalAccount:
            logger.warning("external_account ADC is not yet supported; returning unimplemented")
            throw ExecPluginError.unimplemented
        }
    }

    // MARK: - Private resolution paths

    private func resolveUserCredentials(_ adc: UserADC) async throws -> AuthInfo {
        logger.debug("Resolving user credentials via refresh-token grant")
        let (token, _) = try await exchange.exchangeRefreshToken(adc: adc)
        return .bearerToken(BearerTokenAuth(token: token))
    }

    private func resolveServiceAccount(_ adc: ServiceAccountADC) async throws -> AuthInfo {
        logger.debug("Resolving service-account credentials via RS256 JWT assertion")
        let jwt: String
        do {
            jwt = try await signer.sign(credentials: adc)
        } catch {
            throw ExecPluginError.parseError(
                detail: "JWT signing failed: \(error)"
            )
        }

        let (token, _) = try await exchange.exchangeJWTAssertion(
            assertion: jwt,
            tokenURI: adc.tokenURI
        )
        return .bearerToken(BearerTokenAuth(token: token))
    }
}

// MARK: - ExecCredential JSON helpers (v1)

/// Namespace for Kubernetes ExecCredential (client.authentication.k8s.io/v1)
/// JSON serialisation helpers used by tests and the adapter itself.
public enum ExecCredentialV1 {

    // MARK: - Codable types

    /// Top-level ExecCredential API object.
    public struct ExecCredential: Codable, Sendable {
        public let apiVersion: String
        public let kind: String
        public let status: Status

        public init(apiVersion: String = "client.authentication.k8s.io/v1",
                    kind: String = "ExecCredential",
                    status: Status) {
            self.apiVersion = apiVersion
            self.kind = kind
            self.status = status
        }
    }

    /// `status` sub-object inside `ExecCredential`.
    public struct Status: Codable, Sendable {
        public let token: String
        public let expirationTimestamp: String?   // RFC 3339 or nil for user tokens

        public init(token: String, expirationTimestamp: String? = nil) {
            self.token = token
            self.expirationTimestamp = expirationTimestamp
        }
    }

    // MARK: - Serialisation

    private static func makeEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }

    private static func formatRFC3339(_ date: Date) -> String {
        // ISO8601DateFormatter is not Sendable; create per call (lightweight).
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.string(from: date)
    }

    /// Builds an `ExecCredential` JSON string from a raw bearer token and
    /// optional expiry. Used by integration consumers and tests.
    public static func json(token: String, expiry: Date? = nil) throws -> String {
        let expirationTimestamp = expiry.map { formatRFC3339($0) }
        let obj = ExecCredential(status: Status(
            token: token,
            expirationTimestamp: expirationTimestamp
        ))
        let data = try makeEncoder().encode(obj)
        return String(decoding: data, as: UTF8.self)
    }
}
