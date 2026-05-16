// ExecCredentialJSONDecoder.swift — SubprocessExecCredentialAdapter
// Decodes the client.authentication.k8s.io/v1 ExecCredential JSON produced by
// exec plugins into domain value types. Foundation-only.

import Foundation
import ClusterConnectivity

// MARK: - ExecCredentialOutput

/// Decoded payload from an exec credential plugin's stdout.
///
/// Maps `status.token` to `.bearerToken` and
/// `status.clientCertificateData` / `status.clientKeyData` to `.clientCert`.
struct ExecCredentialOutput: Sendable {
    let authInfo: AuthInfo
}

// MARK: - ExecCredentialJSONDecoder

/// Parses raw `client.authentication.k8s.io/v1` JSON into an
/// `ExecCredentialOutput`. Supports `v1`, `v1beta1`, and `v1alpha1` envelopes.
enum ExecCredentialJSONDecoder {

    /// Decodes `data` and returns the first usable `AuthInfo` found in
    /// `status`. Preference: bearer token > client cert.
    ///
    /// - Throws: `ExecPluginError.parseError` when the JSON is malformed or
    ///   the status carries no usable credential.
    static func decode(_ data: Data) throws -> ExecCredentialOutput {
        let wire: WireExecCredential
        do {
            wire = try JSONDecoder().decode(WireExecCredential.self, from: data)
        } catch {
            throw ExecPluginError.parseError(
                detail: "JSON decode failed: \(error.localizedDescription)"
            )
        }

        let status = wire.status
        if let token = status?.token, !token.isEmpty {
            return ExecCredentialOutput(authInfo: .bearerToken(BearerTokenAuth(token: token)))
        }

        if let cert = status?.clientCertificateData, let key = status?.clientKeyData,
           !cert.isEmpty, !key.isEmpty {
            return ExecCredentialOutput(
                authInfo: .clientCert(ClientCertAuth(certPEM: cert, keyPEM: key))
            )
        }

        throw ExecPluginError.parseError(
            detail: "ExecCredential status carries neither token nor clientCertificateData/clientKeyData"
        )
    }
}

// MARK: - Wire types (private)

/// Top-level `ExecCredential` envelope as specified by the Kubernetes exec
/// plugin protocol.
private struct WireExecCredential: Decodable {
    /// `client.authentication.k8s.io/v1` (also v1beta1 / v1alpha1).
    let apiVersion: String
    let kind: String
    let status: WireStatus?

    enum CodingKeys: String, CodingKey {
        case apiVersion
        case kind
        case status
    }
}

/// `ExecCredentialStatus` fields relevant to credential resolution.
private struct WireStatus: Decodable {
    let token: String?
    let clientCertificateData: String?
    let clientKeyData: String?
    let expirationTimestamp: String?
}
