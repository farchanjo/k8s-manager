// SubprocessExecCredentialAdapter.swift — infrastructure adapter placeholder
// Implements: ExecCredentialPort from ClusterConnectivity
//             (exec-based credential plugins via kubeconfig exec: stanza)
// Library: Foundation.Process — no third-party SwiftPM dependency.
// ADR-0018 sandbox caveat: macOS App Sandbox disallows arbitrary Process
// execution unless a temporary-exception entitlement is declared or the
// executable is placed in an explicitly allowed path. Review entitlements
// before shipping this adapter in a sandboxed target.
// Status: skeleton; port implementations pending domain ports definition.
import Foundation

/// Namespace marker for the SubprocessExecCredentialAdapter adapter target.
///
/// Concrete actor types implementing the domain ports land under this enum
/// in subsequent rounds. This file exists so the target compiles cleanly
/// under Swift 6 strict concurrency with the imported infrastructure library.
public enum SubprocessExecCredentialAdapter: Sendable {
    public static let moduleVersion = "0.0.1-skeleton"
}
