// Tests/K8sManagerAppTests/SingleInstanceLockTests.swift
// Tests: SingleInstanceLock — ADR-0042.
//
// Uses a temporary directory to avoid polluting Application Support.

import Testing
import Foundation

// SingleInstanceLock lives in the K8sManagerApp executable target.
// All symbols under test are declared public and importable without @testable.
import K8sManagerApp

@Suite("SingleInstanceLock — ADR-0042")
struct SingleInstanceLockTests {

    // MARK: Helpers

    /// Returns a fresh temporary directory path for each test.
    private func tempLockPath(suffix: String = "") -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("K8sManagerAppTests-\(UUID().uuidString)\(suffix)")
            .path
        return dir + "/.instance.lock"
    }

    // MARK: Tests

    @Test("First acquirer succeeds and creates lock file")
    func firstAcquirerSucceeds() throws {
        let path = tempLockPath()
        try SingleInstanceLock.acquireOrExit(lockPath: path)
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test("Lock file contains current PID after acquisition")
    func lockFileContainsPID() throws {
        let path = tempLockPath(suffix: "-pid")
        try SingleInstanceLock.acquireOrExit(lockPath: path)
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let firstLine = content.split(separator: "\n").first.map(String.init) ?? ""
        let pid = Int(firstLine)
        #expect(pid == Int(ProcessInfo.processInfo.processIdentifier))
    }

    @Test("Second call on same path within the same process succeeds (re-entrant flock)")
    func sameProcessSecondAcquireSucceeds() throws {
        // POSIX flock is per open-file-description; a second open() in the same
        // process creates a new description and upgrades the lock — it does NOT
        // block against itself. This test documents that expected behaviour.
        let path = tempLockPath(suffix: "-reentrant")
        try SingleInstanceLock.acquireOrExit(lockPath: path)
        // A second call should not throw — same process, advisory lock upgrade.
        try SingleInstanceLock.acquireOrExit(lockPath: path)
    }
}
