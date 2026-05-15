// Ports/ExecPluginPort.swift — cluster_connectivity bounded context
// DDD role: Port (outbound — exec credential plugin invocation)
// Narrative ref: domain/narrative.md §Tactical roles (ExecPluginPort)

import Foundation
import SharedKernel

// MARK: - ExecPluginPort

/// Invokes an external exec credential plugin and returns the resolved
/// `AuthInfo`.
///
/// Declared in the domain core; implemented by `SubprocessExecCredentialAdapter`
/// (and cloud-provider-specific adapters). The domain core never imports
/// `Foundation.Process` or any subprocess-management library.
public protocol ExecPluginPort: Sendable {
    /// Invokes the exec plugin described by `auth` and returns the resolved
    /// credentials as an `AuthInfo` value.
    ///
    /// - Parameter auth: The exec-plugin parameters parsed from the kubeconfig
    ///   user entry.
    /// - Returns: A resolved `AuthInfo` value (client-cert or bearer-token) for
    ///   use in exactly one outgoing HTTP request.
    /// - Throws: `ExecPluginError` when the plugin exits non-zero or its output
    ///   cannot be parsed.
    func resolve(auth: ExecPluginAuth) async throws -> AuthInfo
}

// MARK: - ExecPluginError

/// Errors raised by `ExecPluginPort` implementations.
public enum ExecPluginError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// The exec plugin process exited with a non-zero status code.
    case nonZeroExit(code: Int32, stderr: String)

    /// The JSON output from the exec plugin could not be parsed into a valid
    /// `ExecCredential` structure.
    case parseError(detail: String)

    /// The exec plugin binary was not found on the system `PATH`.
    case commandNotFound(command: String)
}

// MARK: - UnimplementedExecPluginPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedExecPluginPort: ExecPluginPort {
    public init() {}

    public func resolve(auth: ExecPluginAuth) async throws -> AuthInfo {
        throw ExecPluginError.unimplemented
    }
}
