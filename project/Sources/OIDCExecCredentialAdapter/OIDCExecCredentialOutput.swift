// OIDCExecCredentialOutput.swift — OIDCExecCredentialAdapter
// DDD role: Adapter output — ExecCredential wire format (client.authentication.k8s.io/v1)
// Ref: https://kubernetes.io/docs/reference/config-api/client-authentication.v1/

import Foundation

// MARK: - ExecCredential (v1 wire format)

/// Kubernetes `ExecCredential` object returned by exec credential plugins.
///
/// Encodes to the exact JSON shape expected by client-go. Only the bearer-token
/// path is implemented here; the client-cert path is left nil.
public struct ExecCredential: Codable, Sendable {

    /// Always `"client.authentication.k8s.io/v1"`.
    public let apiVersion: String

    /// Always `"ExecCredential"`.
    public let kind: String

    /// The resolved credential status block.
    public let status: Status

    public init(idToken: String, expirationTimestamp: Date?) {
        self.apiVersion = "client.authentication.k8s.io/v1"
        self.kind = "ExecCredential"
        self.status = Status(token: idToken, expirationTimestamp: expirationTimestamp)
    }

    // MARK: Status

    /// The credential payload returned in `status`.
    public struct Status: Codable, Sendable {

        /// The bearer token value passed verbatim in the `Authorization: Bearer` header.
        public let token: String

        /// Optional RFC 3339 expiry timestamp — kubeconfig consumers use this to
        /// decide when to call the plugin again without waiting for a 401.
        public let expirationTimestamp: Date?

        private enum CodingKeys: String, CodingKey {
            case token
            case expirationTimestamp
        }

        public init(token: String, expirationTimestamp: Date?) {
            self.token = token
            self.expirationTimestamp = expirationTimestamp
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(token, forKey: .token)
            if let exp = expirationTimestamp {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                try container.encode(iso.string(from: exp), forKey: .expirationTimestamp)
            }
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            token = try container.decode(String.self, forKey: .token)
            if let raw = try container.decodeIfPresent(String.self, forKey: .expirationTimestamp) {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                expirationTimestamp = iso.date(from: raw)
            } else {
                expirationTimestamp = nil
            }
        }
    }
}
