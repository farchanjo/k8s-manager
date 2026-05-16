// GRDBHelmAuditLogAdapterTests.swift — GRDBPersistenceAdapterTests
// Coverage: record() inserts a row, multiple entries accumulate, action filter,
//           AuditLogError.unimplemented sentinel, schema migration applied cleanly.
// ADR ref: ADR-0015 §Rollback (audit entry before API call)

import XCTest
import Foundation
import GRDB
@testable import GRDBPersistenceAdapter
import HelmManagement

// MARK: - GRDBHelmAuditLogAdapterTests

final class GRDBHelmAuditLogAdapterTests: XCTestCase {

    // MARK: - Setup

    private var queue: DatabaseQueue!
    private var adapter: GRDBHelmAuditLogAdapter!

    override func setUp() async throws {
        try await super.setUp()
        queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v4_all") { db in
            try SchemaMigrator._runV4(db)
        }
        try migrator.migrate(queue)
        adapter = GRDBHelmAuditLogAdapter(db: queue)
    }

    // MARK: - 1. Migration produces helm_audit_log table

    func test_schema_helmAuditLogTableExists() throws {
        let exists = try queue.read { db in
            try db.tableExists("helm_audit_log")
        }
        XCTAssertTrue(exists, "helm_audit_log table should exist after v4 migration")
    }

    // MARK: - 2. record() inserts a single row

    func test_record_insertsRow_rowCountIsOne() async throws {
        let entry = makeEntry(action: .rollbackSucceeded)
        try await adapter.record(entry)

        let count = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM helm_audit_log") ?? 0
        }
        XCTAssertEqual(count, 1)
    }

    // MARK: - 3. record() persists all entry fields correctly

    func test_record_persistsAllFields() async throws {
        let releaseId = UUID()
        let entry = HelmAuditEntry(
            releaseId: releaseId,
            revision: 3,
            action: .rollbackFailed,
            operator: "k8smanager-uuid-user@example.com",
            timestamp: "2024-06-15T12:00:00Z",
            detail: "SSA apply failed"
        )
        try await adapter.record(entry)

        let row = try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM helm_audit_log")
        }
        let fetched = try XCTUnwrap(row)
        XCTAssertEqual(fetched["release_id"] as String, releaseId.uuidString)
        XCTAssertEqual(fetched["revision"] as Int, 3)
        XCTAssertEqual(fetched["action"] as String, HelmAuditAction.rollbackFailed.rawValue)
        XCTAssertEqual(fetched["operator_identity"] as String, "k8smanager-uuid-user@example.com")
        XCTAssertEqual(fetched["timestamp"] as String, "2024-06-15T12:00:00Z")
        XCTAssertEqual(fetched["detail"] as String?, "SSA apply failed")
    }

    // MARK: - 4. record() with nil detail stores NULL

    func test_record_nilDetail_storesNull() async throws {
        let entry = makeEntry(action: .rollbackSucceeded, detail: nil)
        try await adapter.record(entry)

        let row = try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT detail FROM helm_audit_log")
        }
        let fetched = try XCTUnwrap(row)
        let detail: String? = fetched["detail"]
        XCTAssertNil(detail, "detail column should be NULL when entry.detail is nil")
    }

    // MARK: - 5. Multiple entries accumulate

    func test_record_threeEntries_rowCountIsThree() async throws {
        try await adapter.record(makeEntry(action: .rollbackSucceeded))
        try await adapter.record(makeEntry(action: .rollbackFailed))
        try await adapter.record(makeEntry(action: .rollbackContention, detail: "holder-abc"))

        let count = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM helm_audit_log") ?? 0
        }
        XCTAssertEqual(count, 3)
    }

    // MARK: - 6. Entries for a specific release can be filtered

    func test_record_filterByReleaseId_returnsOnlyMatchingRows() async throws {
        let targetId = UUID()
        let otherId = UUID()
        try await adapter.record(makeEntry(releaseId: targetId, action: .rollbackSucceeded))
        try await adapter.record(makeEntry(releaseId: targetId, action: .rollbackFailed))
        try await adapter.record(makeEntry(releaseId: otherId, action: .rollbackSucceeded))

        let count = try queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM helm_audit_log WHERE release_id = ?",
                arguments: [targetId.uuidString]
            ) ?? 0
        }
        XCTAssertEqual(count, 2)
    }

    // MARK: - 7. UnimplementedAuditLogPort throws .unimplemented

    func test_unimplementedAuditLogPort_throwsUnimplemented() async {
        let port = UnimplementedAuditLogPort()
        let entry = makeEntry(action: .rollbackSucceeded)
        do {
            try await port.record(entry)
            XCTFail("Expected AuditLogError.unimplemented")
        } catch AuditLogError.unimplemented {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeEntry(
        releaseId: UUID = UUID(),
        action: HelmAuditAction,
        detail: String? = nil
    ) -> HelmAuditEntry {
        HelmAuditEntry(
            releaseId: releaseId,
            revision: 1,
            action: action,
            operator: "k8smanager-test-user@example.com",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            detail: detail
        )
    }
}
