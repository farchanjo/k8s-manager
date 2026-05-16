// K8sManagerApp/SingleInstanceLock.swift — composition root
// DDD role: infrastructure utility
// ADR ref: ADR-0042 (single-instance enforcement via flock)

import AppKit
import Foundation

#if canImport(Darwin)
import Darwin
#endif

// MARK: - SingleInstanceError

/// Errors thrown by ``SingleInstanceLock/acquireOrExit(lockPath:)``.
public enum SingleInstanceError: Error, Sendable {
    /// Another process is already holding the lock.
    ///
    /// ``existingPid`` is read from the lock file when available; it may be
    /// `nil` when the file exists but its contents are malformed.
    case alreadyRunning(existingPid: pid_t?)
    /// The lock file directory could not be created.
    case directoryCreationFailed(path: String, underlying: Error)
    /// The lock file could not be opened for writing.
    case lockFileOpenFailed(path: String, underlying: Error)
    /// An unexpected `flock(2)` error occurred.
    case flockFailed(errno: Int32)
}

// MARK: - SingleInstanceLock

/// POSIX `flock(2)`-based single-instance guard (ADR-0042).
///
/// Call ``acquireOrExit(lockPath:)`` as the very first step of ``K8sManagerApp``
/// bootstrap. On success the current process holds an exclusive advisory lock on
/// the file for the duration of its lifetime — the kernel releases it
/// automatically on process exit or file-descriptor close.
///
/// On lock contention the method throws ``SingleInstanceError/alreadyRunning(existingPid:)``
/// so the call-site can activate the existing window via `NSRunningApplication`
/// before exiting.
public enum SingleInstanceLock {

    // MARK: Public API

    /// Acquires an exclusive non-blocking `flock` on `lockPath`.
    ///
    /// On success: creates parent directories if needed, opens the file,
    /// acquires `LOCK_EX | LOCK_NB`, and writes the current PID + bundle
    /// identifier to the file (for diagnostics).
    ///
    /// On contention: reads the existing PID from the file and throws
    /// ``SingleInstanceError/alreadyRunning(existingPid:)``.
    ///
    /// The call site is responsible for catching the error and either
    /// activating the existing instance via `NSRunningApplication` or calling
    /// `NSApp.terminate(nil)`.
    ///
    /// - Parameter lockPath: Absolute path to the lock file.
    ///   Recommended: `<applicationSupport>/K8sManager/.instance.lock`
    /// - Throws: ``SingleInstanceError`` on failure.
    public static func acquireOrExit(lockPath: String) throws {
        let url = URL(fileURLWithPath: lockPath)
        let directory = url.deletingLastPathComponent().path

        // Ensure the parent directory exists.
        do {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw SingleInstanceError.directoryCreationFailed(path: directory, underlying: error)
        }

        // Open (or create) the lock file for reading and writing.
        // O_RDWR | O_CREAT — we need write access to update the PID.
        let fd = open(lockPath, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else {
            let err = errno
            throw SingleInstanceError.lockFileOpenFailed(
                path: lockPath,
                underlying: NSError(domain: NSPOSIXErrorDomain, code: Int(err))
            )
        }
        // NOTE: fd is intentionally kept open for the process lifetime
        // so the kernel maintains the advisory lock until exit.

        // Attempt a non-blocking exclusive lock.
        let result = flock(fd, LOCK_EX | LOCK_NB)
        if result != 0 {
            let flockErrno = errno
            if flockErrno == EWOULDBLOCK || flockErrno == EAGAIN {
                // Another process holds the lock — try to read its PID.
                let existingPid = readPID(from: fd)
                close(fd)
                throw SingleInstanceError.alreadyRunning(existingPid: existingPid)
            }
            close(fd)
            throw SingleInstanceError.flockFailed(errno: flockErrno)
        }

        // We hold the lock. Overwrite the file with current PID + bundle ID.
        writeLockContents(fd: fd)
    }

    // MARK: Private helpers

    /// Reads the first decimal integer from the file descriptor as a `pid_t`.
    private static func readPID(from fd: Int32) -> pid_t? {
        var buffer = [UInt8](repeating: 0, count: 64)
        let bytesRead = read(fd, &buffer, buffer.count - 1)
        guard bytesRead > 0 else { return nil }
        let str = String(bytes: buffer.prefix(Int(bytesRead)), encoding: .utf8) ?? ""
        let first = str.split(separator: "\n").first ?? Substring(str)
        return pid_t(first.trimmingCharacters(in: .whitespaces))
    }

    /// Truncates the file and writes `<pid>\n<bundleId>\n`.
    private static func writeLockContents(fd: Int32) {
        _ = ftruncate(fd, 0)
        _ = lseek(fd, 0, SEEK_SET)
        let bundleId = Bundle.main.bundleIdentifier ?? "com.k8smanager.unknown"
        let content = "\(ProcessInfo.processInfo.processIdentifier)\n\(bundleId)\n"
        let bytes = Array(content.utf8)
        _ = write(fd, bytes, bytes.count)
    }
}
