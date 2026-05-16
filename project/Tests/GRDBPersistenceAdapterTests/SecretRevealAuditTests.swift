// Tests/GRDBPersistenceAdapterTests/SecretRevealAuditTests.swift
// Coverage: GRDBSecretRevealAudit write + read, HMAC chain link, no-secret-value storage.
// ADR ref: ADR-0063 §Integration tests

import XCTest
import Foundation
import GRDB
@testable import GRDBPersistenceAdapter
import LocalPersistence

// MARK: - SecretRevealAuditTests

final class SecretRevealAuditTests: XCTestCase {

    private var db: DatabaseQueue!
    private var sut: GRDBSecretRevealAudit!
    private let testKey = Data(repeating: 0xCA, count: 32)

    override func setUp() async throws {
        try await super.setUp()
        db = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v3_all") { db in
            try SchemaMigrator._runV3(db)
        }
        try migrator.migrate(db)
        sut = GRDBSecretRevealAudit(db: db, keyProvider: { [testKey] in testKey })
    }

    // MARK: - 1. Single reveal entry appended

    func test_append_reveal_writesOneRow() async throws {
        let entry = makeEntry(action: .reveal, keyName: "password")

        let returnedId = try await sut.append(entry: entry)

        XCTAssertEqual(returnedId, entry.id)
        let count = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM secret_reveal_audit") ?? 0
        }
        XCTAssertEqual(count, 1)
    }

    // MARK: - 2. Audit row does not contain the decoded value

    func test_append_rowDoesNotContainDecodedValue() async throws {
        let sensitiveValue = "super-secret-password-12345"
        let entry = makeEntry(action: .reveal, keyName: "token")

        _ = try await sut.append(entry: entry)

        // Scan every column in every row for the sensitive value.
        let rows = try await db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM secret_reveal_audit")
        }
        for row in rows {
            for col in row.columnNames {
                let cellValue = row[col] as? String ?? ""
                XCTAssertFalse(
                    cellValue.contains(sensitiveValue),
                    "Column \(col) unexpectedly contained sensitive value"
                )
            }
        }
    }

    // MARK: - 3. HMAC chain links entries

    func test_append_twoEntries_secondRowHasNonGenesisDigest() async throws {
        let first = makeEntry(action: .reveal, keyName: ".dockerconfigjson")
        let second = makeEntry(action: .clipboardCopy)

        _ = try await sut.append(entry: first)
        _ = try await sut.append(entry: second)

        let rows = try await db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT previous_entry_digest, entry_digest FROM secret_reveal_audit ORDER BY requested_at ASC"
            )
        }
        XCTAssertEqual(rows.count, 2)

        // First row previous digest = genesis
        let firstPrev: String = rows[0]["previous_entry_digest"]
        XCTAssertEqual(firstPrev, SecretRevealEntry.genesisDigest)

        // Second row previous digest = first row entry digest
        let firstDigest: String = rows[0]["entry_digest"]
        let secondPrev: String = rows[1]["previous_entry_digest"]
        XCTAssertEqual(secondPrev, firstDigest)
        XCTAssertNotEqual(secondPrev, SecretRevealEntry.genesisDigest)
    }

    // MARK: - 4. Entry digest is 64 hex characters

    func test_append_entryDigestIs64LowercaseHex() async throws {
        _ = try await sut.append(entry: makeEntry(action: .reveal, keyName: "token"))

        let digest = try await db.read { db in
            try String.fetchOne(db, sql: "SELECT entry_digest FROM secret_reveal_audit LIMIT 1")
        }
        let unwrapped = try XCTUnwrap(digest)
        XCTAssertEqual(unwrapped.count, 64)
        XCTAssertTrue(unwrapped.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    // MARK: - 5. Keyed by action value

    func test_append_storesActionRawValue() async throws {
        _ = try await sut.append(entry: makeEntry(action: .autoHide, keyName: "tls.key"))

        let action = try await db.read { db in
            try String.fetchOne(db, sql: "SELECT action FROM secret_reveal_audit LIMIT 1")
        }
        XCTAssertEqual(action, "auto-hide")
    }

    // MARK: - 6. Keychaining locked port throws

    func test_append_keychainLocked_throws() async throws {
        let lockedSut = GRDBSecretRevealAudit(db: db, keyProvider: { nil })
        do {
            _ = try await lockedSut.append(entry: makeEntry(action: .reveal, keyName: "x"))
            XCTFail("Expected keychainLocked to be thrown")
        } catch SecretRevealAuditError.keychainLocked {
            // expected
        }
    }

    // MARK: Helpers

    private func makeEntry(
        action: SecretRevealAction,
        keyName: String = "password"
    ) -> SecretRevealEntry {
        SecretRevealEntry(
            id: UUID(),
            clusterId: UUID(),
            namespace: "default",
            secretName: "my-secret",
            secretType: "kubernetes.io/dockerconfigjson",
            keyName: keyName,
            action: action,
            userIdentifier: "testuser",
            requestedAt: Date(),
            previousEntryDigest: SecretRevealEntry.genesisDigest
        )
    }
}

