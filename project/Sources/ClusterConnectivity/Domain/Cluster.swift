// Domain/Cluster.swift — cluster_connectivity bounded context
// DDD role: Entity (lives inside the Kubeconfig aggregate)
// CUE source: docs/arch/contexts/cluster_connectivity/schemas/cluster.cue

import Foundation
import SharedKernel

// MARK: - CAStrategy

/// How the application trusts the cluster's API server certificate.
///
/// Mirrors `#CAStrategy` from `cluster.cue`. Exactly one case is set at any
/// time; the discriminant maps to the CUE `kind` field.
public enum CAStrategy: Hashable, Sendable, Codable {
    /// Uses the macOS trust store. Common for managed clusters whose API
    /// server has a publicly-trusted certificate.
    case system

    /// Carries inline PEM bytes decoded from `certificate-authority-data`.
    case embedded(pemData: String)

    /// Carries the absolute path of a CA bundle on disk
    /// (`certificate-authority`).
    case referenced(path: String)
}

// MARK: - Cluster

/// Domain entity assembled from a kubeconfig `clusters[]` entry plus its
/// resolved certificate authority.
///
/// Mirrors `#Cluster` from `cluster.cue`. Identified by a `ClusterId` from
/// the shared kernel. Mutable only through aggregate operations on the
/// owning `Kubeconfig` aggregate root.
public struct Cluster: Hashable, Sendable, Codable {
    /// Shared-kernel identifier — SHA-256 of `<sourcePath>::<name>`, truncated
    /// to 16 bytes, rendered as a UUIDv7-shaped string.
    public let id: ClusterId

    /// Mirrors the kubeconfig `clusters[].name` field; used as the cluster
    /// display name unless the operator explicitly renames it in
    /// `context_navigation`.
    public let name: String

    /// API server URL. Always HTTPS in practice; HTTP is permitted for local
    /// development clusters (kind, k3d).
    public let server: String

    /// Certificate authority trust strategy.
    public let caStrategy: CAStrategy

    /// When `true`, TLS verification is disabled. The UI surfaces a prominent
    /// warning and declines to persist credentials beyond the current process.
    public let insecureSkipTLSVerify: Bool

    public init(
        id: ClusterId,
        name: String,
        server: String,
        caStrategy: CAStrategy,
        insecureSkipTLSVerify: Bool
    ) {
        self.id = id
        self.name = name
        self.server = server
        self.caStrategy = caStrategy
        self.insecureSkipTLSVerify = insecureSkipTLSVerify
    }
}
