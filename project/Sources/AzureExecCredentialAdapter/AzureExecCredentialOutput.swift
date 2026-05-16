// AzureExecCredentialOutput.swift — AzureExecCredentialAdapter target
// DDD role: Infrastructure value object (ExecCredential JSON wrapper)
// Spec: client.authentication.k8s.io/v1 ExecCredential API object

import Foundation

// MARK: - ExecCredentialV1

/// Codable representation of the Kubernetes ExecCredential API object
/// (`client.authentication.k8s.io/v1`).
///
/// Produced by exec credential adapter implementations and serialised to JSON
/// for consumption by kubectl-compatible clients.  Only the bearer-token
/// status field is populated by the Azure adapter; client-certificate fields
/// are out of scope for MSAL-backed authentication.
///
/// Reference: https://kubernetes.io/docs/reference/config-api/client-authentication.v1/
public struct ExecCredentialV1: Codable, Sendable, Equatable {
    // MARK: Nested types

    /// The `status` object embedded in an ExecCredential.
    public struct Status: Codable, Sendable, Equatable {
        /// Short-lived bearer token.
        public let token: String

        /// RFC 3339 timestamp after which the token must no longer be used.
        /// When `nil` the client treats the token as non-expiring.
        public let expirationTimestamp: String?

        public init(token: String, expirationTimestamp: String?) {
            self.token = token
            self.expirationTimestamp = expirationTimestamp
        }
    }

    // MARK: Top-level fields

    /// Fixed to `"client.authentication.k8s.io/v1"`.
    public let apiVersion: String

    /// Fixed to `"ExecCredential"`.
    public let kind: String

    /// Resolved credential status.
    public let status: Status

    // MARK: Init

    /// Creates an ExecCredential with a bearer token and optional expiry.
    ///
    /// - Parameters:
    ///   - token: The bearer token value.
    ///   - expirationTimestamp: Optional RFC 3339 expiry timestamp.
    public init(token: String, expirationTimestamp: String?) {
        self.apiVersion = "client.authentication.k8s.io/v1"
        self.kind = "ExecCredential"
        self.status = Status(token: token, expirationTimestamp: expirationTimestamp)
    }

    // MARK: JSON encoding

    /// Returns the compact JSON representation of this ExecCredential.
    ///
    /// - Throws: `EncodingError` when the encoder cannot serialise the value
    ///   (should not occur in practice — all fields are basic Swift types).
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - RFC 3339 date helper

extension Date {
    /// Formats the receiver as an RFC 3339 string suitable for the
    /// `expirationTimestamp` field of an ExecCredential status.
    var rfc3339: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}
