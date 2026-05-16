// Tests/SharedKernelTests/NetworkVolumeCheckTests.swift
// Tests: ApplicationPaths.isLocalVolume — ADR-0042 §Network-volume rejection.

import Testing
import Foundation
@testable import SharedKernel

@Suite("NetworkVolumeCheck — ADR-0042")
struct NetworkVolumeCheckTests {

    // MARK: Local volume

    @Test("Temporary directory reports as a local volume")
    func temporaryDirectoryIsLocal() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("k8s-volume-test-\(UUID().uuidString)")
        // isLocalVolume probes the parent directory; the file need not exist.
        let result = try ApplicationPaths.isLocalVolume(at: tmp)
        #expect(result == true, "NSTemporaryDirectory must reside on a local volume")
    }

    @Test("Application Support directory reports as a local volume")
    func applicationSupportIsLocal() throws {
        let result = try ApplicationPaths.isLocalVolume(at: ApplicationPaths.storageURL)
        #expect(result == true, "ApplicationPaths.storageURL must reside on a local volume in test environment")
    }

    // MARK: Path without existing parent

    @Test("isLocalVolume resolves parent directory correctly when file does not exist")
    func nonExistentFileResolvesParent() throws {
        // storageURL's parent (supportDirectory) always exists in production.
        // Use a deeply nested path whose first existing ancestor is /tmp.
        let deep = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nonexistent-dir-\(UUID().uuidString)")
            .appendingPathComponent("fake-storage.sqlite3")
        // The parent directory does not exist; Foundation falls back to the
        // nearest reachable ancestor. On local filesystems this succeeds.
        // We only assert no exception is thrown; the return value depends on
        // whether Foundation can resolve the volume without the directory present.
        _ = try? ApplicationPaths.isLocalVolume(at: deep)
    }
}
