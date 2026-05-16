// SubprocessExecCredentialAdapter.swift — infrastructure adapter
// Implements: ExecPluginPort from ClusterConnectivity
//             (exec-based credential plugins via kubeconfig exec: stanza)
// Library: Foundation.Process — no third-party SwiftPM dependency.
// ADR-0018 sandbox caveat: macOS App Sandbox disallows arbitrary Process
// execution unless a temporary-exception entitlement is declared or the
// executable is placed in an explicitly allowed path. Review entitlements
// before shipping this adapter in a sandboxed target.
// ADR-0033: command path is validated against a caller-supplied allowlist
// before any subprocess is spawned.

import Foundation
import ClusterConnectivity

// MARK: - SubprocessExecCredentialAdapter

/// Generic fallback adapter for any kubeconfig `exec:` plugin not natively
/// handled by a cloud-provider-specific adapter (e.g. `kubelogin`,
/// `gke-gcloud-auth-plugin`, custom binaries).
///
/// Validates the command path against an allowlist, spawns the subprocess via
/// `ProcessRunner`, enforces a 30-second timeout, then decodes the
/// `client.authentication.k8s.io/v1` JSON from stdout into an `AuthInfo`
/// value suitable for a single outgoing HTTP request.
///
/// Thread safety: `actor` isolation guarantees that all mutable state
/// (including the allowlist closure) is accessed from a single concurrency
/// domain, satisfying Swift 6 strict concurrency.
public actor SubprocessExecCredentialAdapter: ExecPluginPort {

    // MARK: Types

    /// Returns `true` when the absolute command path is permitted to execute.
    ///
    /// Callers implement domain-specific allowlist logic (path prefix checks,
    /// SHA-256 pin, Rego evaluation, etc.). The closure must be `Sendable`
    /// because it crosses actor boundaries.
    public typealias AllowlistPredicate = @Sendable (String) -> Bool

    // MARK: Stored properties

    private let isCommandAllowed: AllowlistPredicate
    private let timeoutSeconds: Int

    // MARK: Init

    /// Designated initialiser.
    ///
    /// - Parameters:
    ///   - allowlist: A `@Sendable` closure that receives an absolute command
    ///     path and returns `true` when execution is permitted. Defaults to an
    ///     open allowlist (permit-all) — **restrict in production**.
    ///   - timeoutSeconds: Wall-clock seconds before the subprocess is killed.
    ///     Defaults to 30.
    public init(
        allowlist: @escaping AllowlistPredicate = { _ in true },
        timeoutSeconds: Int = 30
    ) {
        self.isCommandAllowed = allowlist
        self.timeoutSeconds = timeoutSeconds
    }

    // MARK: ExecPluginPort

    /// Resolves credentials by invoking the exec plugin described by `auth`.
    ///
    /// Execution steps:
    /// 1. Resolve the absolute executable path via `PATH` lookup when `command`
    ///    is a bare name.
    /// 2. Validate the resolved path against the caller-supplied allowlist.
    /// 3. Spawn the process with merged environment and the provided arguments.
    /// 4. Wait up to `timeoutSeconds`; kill + throw on expiry.
    /// 5. Check exit code; throw `ExecPluginError.nonZeroExit` on failure.
    /// 6. Decode stdout as `ExecCredential` v1 JSON and return `AuthInfo`.
    ///
    /// - Parameter auth: Exec-plugin parameters from the kubeconfig user entry.
    /// - Returns: A resolved `AuthInfo` (bearer token or client cert).
    /// - Throws: `ExecPluginError` on allowlist rejection, non-zero exit,
    ///   timeout, or parse failure.
    public func resolve(auth: ExecPluginAuth) async throws -> AuthInfo {
        let resolvedCommand = try resolveCommandPath(auth.command)

        guard isCommandAllowed(resolvedCommand) else {
            throw ExecPluginError.commandNotFound(command: resolvedCommand)
        }

        let pluginEnv = Dictionary(
            auth.env.map { ($0.name, $0.value) },
            uniquingKeysWith: { _, last in last }
        )

        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(
                command: resolvedCommand,
                arguments: auth.args,
                environment: pluginEnv,
                timeoutSeconds: timeoutSeconds
            )
        } catch let runnerError as ProcessRunnerError {
            switch runnerError {
            case .subprocessTimeout(let cmd, _):
                // Re-map to domain error; the domain port does not expose
                // ProcessRunnerError directly.
                throw ExecPluginError.nonZeroExit(
                    code: -1,
                    stderr: "timeout: \(cmd) exceeded \(timeoutSeconds)s"
                )
            }
        }

        guard result.exitCode == 0 else {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? "<binary stderr>"
            throw ExecPluginError.nonZeroExit(code: result.exitCode, stderr: stderr)
        }

        let output = try ExecCredentialJSONDecoder.decode(result.stdout)
        return output.authInfo
    }

    // MARK: - Private helpers

    /// Resolves a bare binary name to an absolute path by walking `PATH`.
    /// Returns the value unchanged if it already starts with `/`.
    private func resolveCommandPath(_ command: String) throws -> String {
        if command.hasPrefix("/") {
            return command
        }
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        for dir in pathEnv.split(separator: ":") {
            let candidate = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw ExecPluginError.commandNotFound(command: command)
    }
}
