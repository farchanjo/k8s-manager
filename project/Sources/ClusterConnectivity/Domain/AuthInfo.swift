// Domain/AuthInfo.swift — cluster_connectivity bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/cluster_connectivity/schemas/auth_info.cue

import Foundation

// MARK: - AuthInfo

/// Immutable, in-memory representation of a resolved credential for a single
/// Kubernetes context.
///
/// Mirrors `#AuthInfo` from `auth_info.cue`. Derived from a `KubeconfigUser`
/// at probe time and discarded as soon as the HTTP request completes. Never
/// persisted, serialised, or logged.
public enum AuthInfo: Hashable, Sendable, Codable {
    /// X.509 client-certificate authentication — the most common form in
    /// development clusters.
    case clientCert(ClientCertAuth)

    /// Static bearer-token authentication.
    case bearerToken(BearerTokenAuth)

    /// External exec credential plugin. The actual `ExecCredential` JSON is
    /// parsed by `ExecPluginPort`; the domain core only carries the
    /// invocation parameters.
    case execPlugin(ExecPluginAuth)
}

// MARK: - ClientCertAuth

/// X.509 client-certificate credentials held in memory.
///
/// Mirrors `#ClientCertAuth` from `auth_info.cue`. The adapter never persists
/// `certPEM` or `keyPEM`.
public struct ClientCertAuth: Hashable, Sendable, Codable {
    /// Decoded PEM certificate bytes. Must begin with
    /// `-----BEGIN CERTIFICATE-----`.
    public let certPEM: String

    /// Decoded PEM private-key bytes. Must begin with
    /// `-----BEGIN (RSA |EC |)PRIVATE KEY-----`.
    public let keyPEM: String

    public init(certPEM: String, keyPEM: String) {
        self.certPEM = certPEM
        self.keyPEM = keyPEM
    }
}

// MARK: - BearerTokenAuth

/// Static bearer token. Rotation is the operator's responsibility.
///
/// Mirrors `#BearerTokenAuth` from `auth_info.cue`.
public struct BearerTokenAuth: Hashable, Sendable, Codable {
    /// The bearer token value. Contains only `[A-Za-z0-9._-]` characters.
    public let token: String

    public init(token: String) {
        self.token = token
    }
}

// MARK: - ExecPluginAuth

/// Parameters needed to invoke an external exec credential plugin.
///
/// Mirrors `#ExecPluginAuth` from `auth_info.cue`. The `ExecCredential` JSON
/// is parsed by `ExecPluginPort` and never stored in the aggregate.
public struct ExecPluginAuth: Hashable, Sendable, Codable {
    /// API version of the exec-plugin protocol.
    /// Matches `^client\.authentication\.k8s\.io/v1(beta1|alpha1)?$`.
    public let apiVersion: String

    /// Executable to invoke for credential refresh.
    public let command: String

    /// Arguments passed to the command.
    public let args: [String]

    /// Environment variables injected into the command's environment.
    public let env: [EnvVar]

    /// When `true`, the full cluster information is passed to the plugin via
    /// stdin.
    public let provideClusterInfo: Bool

    /// Human-readable hint shown to the operator when the plugin is not
    /// installed.
    public let installHint: String?

    public init(
        apiVersion: String,
        command: String,
        args: [String] = [],
        env: [EnvVar] = [],
        provideClusterInfo: Bool = false,
        installHint: String? = nil
    ) {
        self.apiVersion = apiVersion
        self.command = command
        self.args = args
        self.env = env
        self.provideClusterInfo = provideClusterInfo
        self.installHint = installHint
    }
}

// MARK: - EnvVar

/// A name/value environment variable pair used by exec credential plugins and
/// kubeconfig exec configurations.
public struct EnvVar: Hashable, Sendable, Codable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}
