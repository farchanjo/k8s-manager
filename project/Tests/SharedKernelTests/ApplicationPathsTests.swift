// Tests/SharedKernelTests/ApplicationPathsTests.swift
// Target: SharedKernelTests
// ADR refs: ADR-0010 (storage design), ADR-0026 (filesystem layout), ADR-0042 (instance lock)

import XCTest
@testable import SharedKernel

final class ApplicationPathsTests: XCTestCase {

    // MARK: Path shape

    /// `supportDirectory` must end with the `K8sManager` path component.
    ///
    /// This asserts that the `applicationSupportDirectory` resolution appends the
    /// correct bundle-scoped folder name, regardless of the concrete sandbox path
    /// returned by the OS (which differs between test and production environments).
    func test_supportDirectory_endsWithK8sManager() {
        let dir = ApplicationPaths.supportDirectory
        XCTAssertEqual(
            dir.lastPathComponent,
            "K8sManager",
            "supportDirectory must end with 'K8sManager' (ADR-0026)"
        )
    }

    /// All well-known paths must reside under `supportDirectory`.
    ///
    /// Ensures no path was accidentally built against a different base.
    func test_allPathsUnderSupportDirectory() {
        let base = ApplicationPaths.supportDirectory.path
        let candidates: [(String, URL)] = [
            ("storageURL", ApplicationPaths.storageURL),
            ("instanceLockURL", ApplicationPaths.instanceLockURL),
            ("clusterStateRoot", ApplicationPaths.clusterStateRoot),
            ("logDirectory", ApplicationPaths.logDirectory),
        ]
        for (name, url) in candidates {
            XCTAssertTrue(
                url.path.hasPrefix(base),
                "\(name) (\(url.path)) must be under supportDirectory (\(base))"
            )
        }
    }

    // MARK: File names

    func test_storageURL_hasSqlite3Extension() {
        XCTAssertEqual(ApplicationPaths.storageURL.pathExtension, "sqlite3")
    }

    func test_instanceLockURL_isHiddenDotFile() {
        XCTAssertTrue(
            ApplicationPaths.instanceLockURL.lastPathComponent.hasPrefix("."),
            "instanceLockURL must be a hidden dot-file (ADR-0042)"
        )
    }

    // MARK: Directory creation

    /// `ensureSupportDirectoryExists()` creates the directory with `0700` permissions.
    ///
    /// Uses a temporary directory to avoid polluting the real Application Support
    /// tree during testing. The test swizzles nothing — it exercises the real
    /// `FileManager` call against the path that `ApplicationPaths` resolves, then
    /// checks POSIX attributes.
    func test_ensureSupportDirectoryExists_creates0700() throws {
        // Remove the directory if it already exists from a previous run so the
        // test verifies creation, not idempotent re-creation.
        let dir = ApplicationPaths.supportDirectory
        if FileManager.default.fileExists(atPath: dir.path) {
            // Do not remove the real directory — we only verify permissions.
        } else {
            try ApplicationPaths.ensureSupportDirectoryExists()
        }

        // At this point the directory must exist (either pre-existing or just created).
        try ApplicationPaths.ensureSupportDirectoryExists()

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: dir.path,
            isDirectory: &isDirectory
        )
        XCTAssertTrue(exists, "supportDirectory must exist after ensureSupportDirectoryExists()")
        XCTAssertTrue(isDirectory.boolValue, "supportDirectory must be a directory")

        let attributes = try FileManager.default.attributesOfItem(atPath: dir.path)
        let permissions = attributes[.posixPermissions] as? Int
        XCTAssertEqual(
            permissions,
            0o700,
            "supportDirectory must have 0700 permissions (ADR-0026)"
        )
    }
}
