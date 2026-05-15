// ClusterParams.swift — value object for cluster connection parameters
// Bounded context: SwiftkubeClientAdapter (infrastructure)
// Purpose: Isolated from SwiftkubeClient imports to avoid AuthInfo ambiguity.

import ClusterConnectivity
import Foundation
import NIOSSL
import SharedKernel

// MARK: - ClusterParams

/// Connection parameters produced by the composition-root resolver.
///
/// Isolated in its own file so that ClusterConnectivity.AuthInfo is
/// unambiguous (SwiftkubeClient also exports an AuthInfo struct).
public struct ClusterParams: Sendable {
    /// API server URL.
    public let server: URL
    /// Domain credential for this cluster.
    public let auth: AuthInfo
    /// When `true`, TLS certificate verification is disabled.
    public let insecureSkipTLSVerify: Bool
    /// Certificate-authority trust strategy.
    public let caStrategy: CAStrategy

    public init(
        server: URL,
        auth: AuthInfo,
        insecureSkipTLSVerify: Bool,
        caStrategy: CAStrategy
    ) {
        self.server = server
        self.auth = auth
        self.insecureSkipTLSVerify = insecureSkipTLSVerify
        self.caStrategy = caStrategy
    }
}

// MARK: - ClusterParams + NIOSSLTrustRoots

extension ClusterParams {

    /// Maps the domain `CAStrategy` to `NIOSSLTrustRoots`.
    ///
    /// Declared here (no SwiftkubeClient import) so NIOSSL types are
    /// unambiguous.
    func trustRoots() throws -> NIOSSLTrustRoots? {
        switch caStrategy {
        case .system:
            return nil
        case .embedded(let pemData):
            let bytes = Array(pemData.utf8)
            let certs = try NIOSSLCertificate.fromPEMBytes(bytes)
            return .certificates(certs)
        case .referenced(let path):
            let certs = try NIOSSLCertificate.fromPEMFile(path)
            return .certificates(certs)
        }
    }

    /// Maps the domain `AuthInfo` to a bearer token string, or throws
    /// `KubernetesApiError.authMethodNotYetImplemented` if the auth method
    /// is not yet supported.
    ///
    /// Returns `nil` when auth is anonymous (no credential — not a
    /// supported case yet but defined for forward compatibility).
    func bearerToken() throws -> String? {
        switch auth {
        case .bearerToken(let info):
            return info.token
        case .clientCert:
            throw KubernetesApiError.authMethodNotYetImplemented
        case .execPlugin:
            throw KubernetesApiError.authMethodNotYetImplemented
        }
    }
}
