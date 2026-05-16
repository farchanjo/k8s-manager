// ProcessRunner.swift — SubprocessExecCredentialAdapter
// Wraps Foundation.Process with a 30-second timeout enforced via
// DispatchSourceTimer. Captures stdout and stderr separately.
// Foundation-only: no third-party dependencies.

import Foundation

// MARK: - ProcessResult

/// Raw output from a completed subprocess.
struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

// MARK: - ProcessRunnerError

enum ProcessRunnerError: Error, Sendable {
    /// The process did not finish within the allowed wall-clock time.
    case subprocessTimeout(command: String, timeoutSeconds: Int)
}

// MARK: - ProcessRunner

/// Launches a subprocess, captures stdout/stderr into memory, and enforces a
/// wall-clock timeout via `DispatchSourceTimer`. The process is killed with
/// SIGTERM followed by SIGKILL when the timer fires.
///
/// Isolation: all mutable state is protected by a `DispatchSemaphore`; the
/// public entry point is async so callers live in the cooperative pool.
enum ProcessRunner {

    static let defaultTimeoutSeconds = 30

    /// Runs `command` with `arguments` and the provided `environment` overlay.
    ///
    /// The provided `environment` is merged on top of the current process
    /// environment: plugin values shadow inherited values for the same key.
    ///
    /// - Parameters:
    ///   - command: Absolute path to the executable.
    ///   - arguments: Command-line arguments passed verbatim.
    ///   - environment: Additional environment variables (merged, not replaced).
    ///   - timeoutSeconds: Maximum wall-clock seconds to wait for the child.
    /// - Returns: A `ProcessResult` with exit code, stdout, and stderr bytes.
    /// - Throws: `ProcessRunnerError.subprocessTimeout` when the timer fires.
    static func run(
        command: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: Int = defaultTimeoutSeconds
    ) async throws -> ProcessResult {
        // Offload the blocking wait to a background executor so the cooperative
        // pool is not held.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try runBlocking(
                        command: command,
                        arguments: arguments,
                        environment: environment,
                        timeoutSeconds: timeoutSeconds
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    /// Synchronous implementation. Must be called from a non-cooperative thread.
    private static func runBlocking(
        command: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: Int
    ) throws -> ProcessResult {

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        // Merge inherited env + plugin-supplied overrides.
        var mergedEnv = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            mergedEnv[key] = value
        }
        process.environment = mergedEnv

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Timeout enforcement — fire once after `timeoutSeconds` wall seconds.
        let timedOut = _MutableBox(false)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        timer.schedule(deadline: .now() + .seconds(timeoutSeconds))
        timer.setEventHandler {
            timedOut.value = true
            // Graceful shutdown first; the OS escalates if the process ignores it.
            process.terminate()
            // Allow a short grace period then force-kill.
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        timer.resume()

        process.waitUntilExit()
        timer.cancel()

        if timedOut.value {
            throw ProcessRunnerError.subprocessTimeout(
                command: command,
                timeoutSeconds: timeoutSeconds
            )
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdoutData,
            stderr: stderrData
        )
    }
}

// MARK: - _MutableBox

/// Thread-safe boolean flag accessed across DispatchSourceTimer and the main
/// wait-path without introducing actor overhead.
private final class _MutableBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool

    init(_ initial: Bool) {
        _value = initial
    }

    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
