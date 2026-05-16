// KeychainAdapterTests.swift — integration tests for KeychainAccessAdapter
// and AuditChainKeyManager using real macOS Keychain with unique test prefixes.
//
// Each test run uses a UUID-scoped service to avoid collisions between runs.
// All items are deleted in tearDown to leave the Keychain clean.

import XCTest
import Foundation
import Security
@testable import KeychainAdapter
import LocalPersistence

// MARK: - KeychainAccessAdapterTests

final class KeychainAccessAdapterTests: XCTestCase {
    private var adapter: KeychainAccessAdapter!
    /// Unique per-run prefix injected into namespace rawValues via test entries.
    private var testRunID: String!

    override func setUp() async throws {
        try await super.setUp()
        // `swift test` runs as an unsigned tool without the Keychain entitlement
        // and gets `errSecMissingEntitlement (-34018)` on every SecItem call.
        // Skip when not running inside a signed app bundle (real-app tests go in
        // an XCUITest target attached to the eventual .app — see ADR-0038).
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["K8SMGR_KEYCHAIN_TESTS"] == nil,
            "Keychain integration tests require a signed bundle; set K8SMGR_KEYCHAIN_TESTS=1 to run."
        )
        adapter = KeychainAccessAdapter()
        testRunID = UUID().uuidString
    }

    override func tearDown() async throws {
        // Best-effort cleanup — errors intentionally suppressed.
        for entry in testEntries() {
            try? await adapter.deleteSecret(for: entry)
        }
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Builds a test `KeychainEntry` using a unique account per test run so
    /// tests remain isolated even when running in parallel.
    private func entry(account: String = "test-account") -> KeychainEntry {
        KeychainEntry(
            namespace: .llm,
            serviceKeySuffix: testRunID,
            account: account,
            label: "Test entry \(testRunID!)",
            maxPayloadBytes: 256
        )
    }

    private func testEntries() -> [KeychainEntry] {
        ["test-account", "account-a", "account-b", "account-c"].map { entry(account: $0) }
    }

    private func payload(_ string: String) -> Data { Data(string.utf8) }

    // MARK: - Tests

    /// Writing then reading returns the identical bytes.
    func test_write_then_read_roundtrips_data() async throws {
        let secret = payload("super-secret-api-key")
        let e = entry()
        try await adapter.writeSecret(secret, for: e)
        let result = try await adapter.readSecret(for: e)
        XCTAssertEqual(result, secret)
    }

    /// Reading a key that was never written throws `.itemNotFound`.
    func test_read_missing_key_throws_itemNotFound() async {
        let e = entry(account: "never-written-\(UUID().uuidString)")
        do {
            _ = try await adapter.readSecret(for: e)
            XCTFail("Expected itemNotFound")
        } catch KeychainAccessError.itemNotFound {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Calling `writeSecret` twice for the same entry updates the value (upsert).
    func test_write_twice_updates_value() async throws {
        let e = entry()
        try await adapter.writeSecret(payload("first"), for: e)
        try await adapter.writeSecret(payload("second"), for: e)
        let result = try await adapter.readSecret(for: e)
        XCTAssertEqual(result, payload("second"))
    }

    /// `listEntries` returns at least as many entries as we wrote.
    func test_listEntries_returns_at_least_written_count() async throws {
        let accounts = ["account-a", "account-b", "account-c"]
        for account in accounts {
            try await adapter.writeSecret(payload("value-\(account)"), for: entry(account: account))
        }
        // Use the base namespace for listing; our entries are under
        // "com.archanjo.K8sManager.llm.<testRunID>" which still falls under .llm.
        let listed = try await adapter.listEntries(namespace: .llm)
        // We cannot assert exact count because other items may exist; just check >= written.
        let testAccounts = listed.filter { $0.serviceKey.contains(testRunID) }
        XCTAssertGreaterThanOrEqual(testAccounts.count, accounts.count)
    }

    /// Deleting a non-existent key is a no-op (no throw).
    func test_delete_nonexistent_is_noop() async throws {
        let e = entry(account: "ghost-\(UUID().uuidString)")
        try await adapter.deleteSecret(for: e) // Must not throw.
    }

    /// After writing and deleting, the subsequent read throws `.itemNotFound`.
    func test_delete_then_read_throws_itemNotFound() async throws {
        let e = entry()
        try await adapter.writeSecret(payload("will-be-deleted"), for: e)
        try await adapter.deleteSecret(for: e)
        do {
            _ = try await adapter.readSecret(for: e)
            XCTFail("Expected itemNotFound after delete")
        } catch KeychainAccessError.itemNotFound {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// An entry that fails `isValid` is rejected with `.invalidEntry`.
    func test_write_invalid_entry_throws_invalidEntry() async {
        let badEntry = KeychainEntry(
            namespace: .llm,
            account: "",  // violates: account must not be empty
            label: "x",
            maxPayloadBytes: 32
        )
        do {
            try await adapter.writeSecret(payload("x"), for: badEntry)
            XCTFail("Expected invalidEntry error")
        } catch KeychainAccessError.invalidEntry(let violations) {
            XCTAssertFalse(violations.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - AuditChainKeyManagerTests

final class AuditChainKeyManagerTests: XCTestCase {
    private var manager: AuditChainKeyManager!
    private var adapter: KeychainAccessAdapter!
    private var auditEntry: KeychainEntry!

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["K8SMGR_KEYCHAIN_TESTS"] == nil,
            "Keychain integration tests require a signed bundle; set K8SMGR_KEYCHAIN_TESTS=1 to run."
        )
        adapter = KeychainAccessAdapter()
        manager = AuditChainKeyManager(keychainAdapter: adapter)
        auditEntry = KeychainEntry(
            namespace: .audit,
            account: AuditChainKey.v1.account,
            label: AuditChainKey.v1.label,
            maxPayloadBytes: 32
        )
        // Pre-clean to simulate fresh install.
        try? await adapter.deleteSecret(for: auditEntry)
    }

    override func tearDown() async throws {
        try? await adapter.deleteSecret(for: auditEntry)
        try await super.tearDown()
    }

    /// First call generates and stores a 256-bit (32-byte) key.
    func test_currentKey_generates_32_byte_key_on_first_call() async throws {
        let key = try await manager.currentKey()
        XCTAssertEqual(key.count, 32)
    }

    /// Second call returns the same key bytes (cached in-memory, not regenerated).
    func test_currentKey_returns_same_bytes_on_subsequent_calls() async throws {
        let first = try await manager.currentKey()
        let second = try await manager.currentKey()
        XCTAssertEqual(first, second)
    }

    /// A fresh manager reading an existing Keychain item returns the stored key.
    func test_currentKey_reads_existing_keychain_item_on_fresh_manager() async throws {
        let key = try await manager.currentKey()

        // Create a fresh manager — no in-memory cache.
        let freshManager = AuditChainKeyManager(keychainAdapter: adapter)
        let fetchedKey = try await freshManager.currentKey()

        XCTAssertEqual(key, fetchedKey)
    }
}
