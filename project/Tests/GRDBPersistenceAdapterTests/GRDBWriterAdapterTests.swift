// GRDBWriterAdapterTests.swift — GRDBPersistenceAdapterTests
// Coverage: write succeeds, read sees committed write, concurrent writes
//           serialize, barrier drains in-flight, error propagates.

import XCTest
import Foundation
import GRDB
@testable import GRDBPersistenceAdapter
import LocalPersistence

// MARK: - GRDBWriterAdapterTests

final class GRDBWriterAdapterTests: XCTestCase {

    // MARK: - Shared in-memory writer

    private var adapter: GRDBWriterAdapter!

    override func setUp() async throws {
        try await super.setUp()
        let queue = try DatabaseQueue()
        try await queue.write { db in
            try db.execute(sql: """
                CREATE TABLE kv (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                )
                """)
        }
        adapter = GRDBWriterAdapter(writer: queue)
    }

    // MARK: - 1. Write succeeds

    /// A synchronous write transaction commits without throwing.
    func test_write_succeeds() throws {
        try adapter.write { handle in
            let db = try XCTUnwrap(handle as? GRDBDatabaseHandle).db
            try db.execute(sql: "INSERT INTO kv VALUES ('a', '1')")
        }
    }

    // MARK: - 2. Read sees committed write

    /// A value written in one transaction is visible in a subsequent read.
    func test_read_sees_committed_write() throws {
        try adapter.write { handle in
            let db = try XCTUnwrap(handle as? GRDBDatabaseHandle).db
            try db.execute(sql: "INSERT INTO kv VALUES ('b', '42')")
        }

        let value: String? = try adapter.read { handle in
            let db = try XCTUnwrap(handle as? GRDBDatabaseHandle).db
            return try String.fetchOne(db, sql: "SELECT value FROM kv WHERE key = 'b'")
        }

        XCTAssertEqual(value, "42")
    }

    // MARK: - 3. Concurrent writes serialize without data loss

    /// Multiple concurrent write tasks all commit; row count matches submission count.
    func test_concurrent_writes_serialize() async throws {
        let count = 20
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                group.addTask { [adapter] in
                    try adapter!.write { handle in
                        let db = try XCTUnwrap(handle as? GRDBDatabaseHandle).db
                        try db.execute(sql: "INSERT OR IGNORE INTO kv VALUES (?, 'v')",
                                       arguments: ["\(index)"])
                    }
                }
            }
            try await group.waitForAll()
        }

        let rowCount: Int = try adapter.read { handle in
            let db = try XCTUnwrap(handle as? GRDBDatabaseHandle).db
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM kv") ?? 0
        }
        XCTAssertEqual(rowCount, count)
    }

    // MARK: - 4. Barrier waits for in-flight writes

    /// `barrier()` returns only after all previously submitted writes are visible.
    func test_barrier_waits_for_inflight_writes() async throws {
        let insertedKey = "barrier_test"

        // Submit a write without awaiting it directly.
        let localAdapter = adapter!
        let writeTask = Task {
            try localAdapter.write { handle in
                let db = try XCTUnwrap(handle as? GRDBDatabaseHandle).db
                try db.execute(sql: "INSERT INTO kv VALUES (?, 'ok')",
                               arguments: [insertedKey])
            }
        }

        // barrier() must drain before we check.
        await adapter.barrier()
        try await writeTask.value

        let found: String? = try adapter.read { handle in
            let db = try XCTUnwrap(handle as? GRDBDatabaseHandle).db
            return try String.fetchOne(db, sql: "SELECT value FROM kv WHERE key = ?",
                                       arguments: [insertedKey])
        }
        XCTAssertEqual(found, "ok")
    }

    // MARK: - 5. Error propagates from work closure

    /// A `DatabaseError` thrown inside `write` is rethrown to the caller.
    func test_error_propagates_from_write_closure() throws {
        XCTAssertThrowsError(
            try adapter.write { handle in
                let db = try XCTUnwrap(handle as? GRDBDatabaseHandle).db
                // Duplicate primary key triggers a UNIQUE constraint error.
                try db.execute(sql: "INSERT INTO kv VALUES ('dup', 'x')")
                try db.execute(sql: "INSERT INTO kv VALUES ('dup', 'y')")
            }
        ) { error in
            XCTAssertTrue(error is DatabaseError,
                          "Expected DatabaseError, got \(type(of: error))")
        }
    }
}
