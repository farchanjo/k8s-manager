// Tests/GRDBPersistenceAdapterTests/GRDBTerminalRepositoryTests.swift
// Coverage: GRDBTerminalRepository — save, loadAll, delete, status normalisation.
// Uses an in-memory DatabaseQueue with the v2 migration applied.

import XCTest
import Foundation
import GRDB
@testable import GRDBPersistenceAdapter
import TerminalSession
import SharedKernel

// MARK: - GRDBTerminalRepositoryTests

final class GRDBTerminalRepositoryTests: XCTestCase {

    private var repo: GRDBTerminalRepository!
    private var queue: DatabaseQueue!

    // MARK: Setup

    override func setUp() async throws {
        try await super.setUp()
        queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v2_schema") { db in
            try SchemaMigrator._runV2(db)
        }
        try migrator.migrate(queue)
        repo = GRDBTerminalRepository(db: queue)
    }

    override func tearDown() async throws {
        repo = nil
        queue = nil
        try await super.tearDown()
    }

    // MARK: - 1. save then loadAll returns the saved session

    func test_save_then_loadAll_returns_persisted_session() async throws {
        let session = makeSession(status: .open)
        try await repo.save(session)

        let all = try await repo.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, session.id)
    }

    // MARK: - 2. save is idempotent (INSERT OR REPLACE)

    func test_save_twice_with_different_status_updates_record() async throws {
        let session = makeSession(status: .open)
        try await repo.save(session)

        let closed = session.withStatus(.closed)
        try await repo.save(closed)

        let all = try await repo.loadAll()
        XCTAssertEqual(all.count, 1)
        // Status is normalised to .closed since it was persisted as closed
        XCTAssertEqual(all[0].status, .closed)
    }

    // MARK: - 3. delete removes the record

    func test_delete_removes_session_from_loadAll() async throws {
        let session = makeSession(status: .closed)
        try await repo.save(session)

        try await repo.delete(id: session.id)

        let all = try await repo.loadAll()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - 4. delete on unknown id silently succeeds

    func test_delete_unknown_id_does_not_throw() async throws {
        let unknownId = UUID()
        // Must not throw
        try await repo.delete(id: unknownId)
    }

    // MARK: - 5. open/opening sessions are normalised to closed on load

    func test_opening_status_is_normalised_to_closed_on_load() async throws {
        let session = makeSession(status: .opening)
        // Directly insert with status "opening" to simulate crash recovery
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO terminal_session
                        (id, cluster_id, namespace, pod, container,
                         kind, status, created_at, last_active_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    session.id.uuidString,
                    session.kubernetesContextId.uuidString,
                    "default", "nginx", nil,
                    "pod_exec", "opening",
                    session.createdAt, session.lastActivityAt
                ]
            )
        }

        let all = try await repo.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].status, .closed,
            "Sessions with status 'opening' at load time must surface as 'closed'")
    }

    // MARK: - 6. loadAll returns sessions ordered by created_at

    func test_loadAll_returns_sessions_in_created_at_order() async throws {
        let first = makeSession(createdAt: "2024-01-01T00:00:00Z", status: .closed)
        let second = makeSession(createdAt: "2024-06-01T00:00:00Z", status: .closed)
        // Insert second first to verify ordering is by column, not insertion order
        try await repo.save(second)
        try await repo.save(first)

        let all = try await repo.loadAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].createdAt, "2024-01-01T00:00:00Z")
        XCTAssertEqual(all[1].createdAt, "2024-06-01T00:00:00Z")
    }

    // MARK: - Helpers

    private func makeSession(
        status: SessionStatus = .open,
        createdAt: String = "2024-01-01T00:00:00Z"
    ) -> TerminalSession {
        TerminalSession(
            kind: .podExec,
            kubernetesContextId: UUIDv7.generate(),
            targetRef: .pod(PodTarget(namespace: "default", podName: "nginx")),
            command: ["/bin/sh"],
            tty: true,
            stdin: true,
            createdAt: createdAt,
            lastActivityAt: createdAt,
            status: status
        )
    }
}
