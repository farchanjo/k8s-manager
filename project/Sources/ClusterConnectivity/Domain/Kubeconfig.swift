// Domain/Kubeconfig.swift — cluster_connectivity bounded context
// DDD role: AggregateRoot
// CUE source: docs/arch/contexts/cluster_connectivity/schemas/kubeconfig.cue

import Foundation
import SharedKernel

// MARK: - Kubeconfig

/// Aggregate root for a single resolved kubeconfig source.
///
/// Mirrors `#Kubeconfig` from `kubeconfig.cue`. Immutable after construction;
/// reload replaces the whole aggregate. Keyed by the absolute, symlink-resolved
/// source path.
public struct Kubeconfig: Hashable, Sendable, Codable {
    /// UUIDv7 generated when the aggregate is first loaded.
    public let id: UUID

    /// Absolute, symlink-resolved path of the source file.
    public let sourcePath: KubeconfigPath

    /// File modification timestamp captured at load time (RFC 3339). Used to
    /// detect external edits without polling.
    public let sourceMTimeRFC3339: String

    /// Mirrors the kubeconfig-level `current-context` field. The application
    /// overrides it via `context_navigation` but preserves the original for
    /// round-tripping diagnostics.
    public let currentContext: String?

    /// Ordered list of cluster entries from the source file.
    public let clusters: [KubeconfigCluster]

    /// Ordered list of user entries from the source file.
    public let users: [KubeconfigUser]

    /// Ordered list of context entries from the source file.
    public let contexts: [KubeconfigContext]

    public init(
        id: UUID = UUIDv7.generate(),
        sourcePath: KubeconfigPath,
        sourceMTimeRFC3339: String,
        currentContext: String? = nil,
        clusters: [KubeconfigCluster] = [],
        users: [KubeconfigUser] = [],
        contexts: [KubeconfigContext] = []
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.sourceMTimeRFC3339 = sourceMTimeRFC3339
        self.currentContext = currentContext
        self.clusters = clusters
        self.users = users
        self.contexts = contexts
    }
}

// MARK: - KubeconfigCluster

/// Raw cluster entry from a kubeconfig file.
///
/// Mirrors `#KubeconfigCluster` from `kubeconfig.cue`. The richer domain
/// `Cluster` is derived from this entry by `ClusterAssembler`.
public struct KubeconfigCluster: Hashable, Sendable, Codable {
    /// Kubeconfig cluster name (display label).
    public let name: String

    /// API server URL.
    public let server: String

    /// Absolute path of a CA bundle on disk (`certificate-authority`).
    public let certificateAuthorityPath: String?

    /// Inline base64-encoded PEM certificate
    /// (`certificate-authority-data`).
    public let certificateAuthorityData: String?

    /// When `true`, TLS verification is disabled. Defaults to `false`.
    public let insecureSkipTLSVerify: Bool

    public init(
        name: String,
        server: String,
        certificateAuthorityPath: String? = nil,
        certificateAuthorityData: String? = nil,
        insecureSkipTLSVerify: Bool = false
    ) {
        self.name = name
        self.server = server
        self.certificateAuthorityPath = certificateAuthorityPath
        self.certificateAuthorityData = certificateAuthorityData
        self.insecureSkipTLSVerify = insecureSkipTLSVerify
    }
}

// MARK: - KubeconfigUser

/// Raw user entry from a kubeconfig file.
///
/// Mirrors `#KubeconfigUser` from `kubeconfig.cue`. Credential material lives
/// here only long enough to be transformed into an `AuthInfo` value object.
public struct KubeconfigUser: Hashable, Sendable, Codable {
    /// Kubeconfig user name.
    public let name: String

    /// Path to a client certificate PEM file.
    public let clientCertificatePath: String?

    /// Inline base64-encoded client certificate PEM.
    public let clientCertificateData: String?

    /// Path to a client private-key PEM file.
    public let clientKeyPath: String?

    /// Inline base64-encoded client private-key PEM.
    public let clientKeyData: String?

    /// Static bearer token.
    public let token: String?

    /// Path to a file containing a bearer token.
    public let tokenFile: String?

    /// Exec credential plugin configuration.
    public let exec: ExecConfig?

    public init(
        name: String,
        clientCertificatePath: String? = nil,
        clientCertificateData: String? = nil,
        clientKeyPath: String? = nil,
        clientKeyData: String? = nil,
        token: String? = nil,
        tokenFile: String? = nil,
        exec: ExecConfig? = nil
    ) {
        self.name = name
        self.clientCertificatePath = clientCertificatePath
        self.clientCertificateData = clientCertificateData
        self.clientKeyPath = clientKeyPath
        self.clientKeyData = clientKeyData
        self.token = token
        self.tokenFile = tokenFile
        self.exec = exec
    }

    // MARK: - ExecConfig

    /// Exec credential plugin configuration nested inside a kubeconfig user.
    ///
    /// Mirrors the `exec` sub-struct of `#KubeconfigUser` in `kubeconfig.cue`.
    public struct ExecConfig: Hashable, Sendable, Codable {
        public let apiVersion: String
        public let command: String
        public let args: [String]
        public let env: [EnvVar]
        public let installHint: String?
        public let provideClusterInfo: Bool

        public init(
            apiVersion: String,
            command: String,
            args: [String] = [],
            env: [EnvVar] = [],
            installHint: String? = nil,
            provideClusterInfo: Bool = false
        ) {
            self.apiVersion = apiVersion
            self.command = command
            self.args = args
            self.env = env
            self.installHint = installHint
            self.provideClusterInfo = provideClusterInfo
        }
    }
}

// MARK: - KubeconfigContext

/// A context entry binding a cluster and a user with an optional default
/// namespace.
///
/// Mirrors `#KubeconfigContext` from `kubeconfig.cue`. The richer domain
/// `ContextId` (shared kernel) is the SHA-256 over `<sourcePath>::<name>`.
public struct KubeconfigContext: Hashable, Sendable, Codable {
    /// Kubeconfig context name (used as display label and lookup key).
    public let name: String

    /// Name of the referenced cluster entry.
    public let cluster: String

    /// Name of the referenced user entry.
    public let user: String

    /// Default namespace for this context. Defaults to `"default"`.
    public let namespace: String

    public init(
        name: String,
        cluster: String,
        user: String,
        namespace: String = "default"
    ) {
        self.name = name
        self.cluster = cluster
        self.user = user
        self.namespace = namespace
    }
}
