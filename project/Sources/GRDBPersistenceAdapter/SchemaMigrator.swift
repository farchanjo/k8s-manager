// SchemaMigrator.swift — GRDBPersistenceAdapter
// DDD role: InfrastructureService (database factory + migration runner)
// ADR refs: ADR-0010 (WAL, PRAGMAs, migrations), ADR-0026 (filesystem path)

import Foundation
import GRDB
import Logging

// MARK: - SchemaMigrator

/// Opens the application SQLite database and runs append-only numbered
/// migrations that match the `storage.dbml` schema.
///
/// Call ``makeQueue(at:logger:)`` once at startup; share the returned
/// ``DatabaseQueue`` across all adapters via the ``GRDBPersistenceAdapter``
/// facade.
public enum SchemaMigrator {

    // MARK: Public factory

    /// Opens (creating if absent) the SQLite file at `path`, applies WAL and
    /// other PRAGMAs from ADR-0010, runs all pending migrations, and returns
    /// the ready-to-use `DatabaseQueue`.
    ///
    /// - Parameters:
    ///   - path: Absolute POSIX path to the `.sqlite3` file.
    ///   - logger: Destination for migration-progress diagnostics.
    public static func makeQueue(at path: String, logger: Logger) throws -> DatabaseQueue {
        try createParentDirectory(for: path)
        var config = Configuration()
        config.prepareDatabase { db in try applyPragmas(to: db) }
        let queue = try DatabaseQueue(path: path, configuration: config)
        try runMigrations(on: queue, logger: logger)
        return queue
    }

    // MARK: Private helpers

    private static func createParentDirectory(for path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private static func applyPragmas(to db: Database) throws {
        try db.execute(sql: "PRAGMA journal_mode=WAL")
        try db.execute(sql: "PRAGMA synchronous=NORMAL")
        try db.execute(sql: "PRAGMA foreign_keys=ON")
        try db.execute(sql: "PRAGMA busy_timeout=5000")
        try db.execute(sql: "PRAGMA cache_size=-65536")
        try db.execute(sql: "PRAGMA wal_autocheckpoint=1000")
    }

    // MARK: Migrations

    private static func runMigrations(on queue: DatabaseQueue, logger: Logger) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial_schema", migrate: v1InitialSchema)
        try migrator.migrate(queue)
        logger.info("SchemaMigrator: all migrations applied")
    }

    /// Exposed for in-memory test helpers in `GRDBPersistenceAdapter.makeInMemory()`.
    /// Not part of the public stable API — prefixed with `_` by convention.
    public static func _runV1(_ db: Database) throws {
        try v1InitialSchema(db)
    }

    // swiftlint:disable function_body_length
    private static func v1InitialSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS chat_sessions (
                id TEXT PRIMARY KEY NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                title TEXT,
                provider_profile_id TEXT,
                cluster_id TEXT,
                archived_at TEXT,
                FOREIGN KEY (provider_profile_id)
                    REFERENCES provider_profiles(id) ON DELETE SET NULL
            )
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_chat_sessions_provider
                ON chat_sessions(provider_profile_id)
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_chat_sessions_archived
                ON chat_sessions(archived_at)
            """)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS chat_messages (
                id TEXT PRIMARY KEY NOT NULL,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                tool_calls_json TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (session_id)
                    REFERENCES chat_sessions(id) ON DELETE CASCADE
            )
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_chat_messages_session_time
                ON chat_messages(session_id, created_at)
            """)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS provider_profiles (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                display_name TEXT NOT NULL,
                endpoint_url TEXT NOT NULL,
                model TEXT NOT NULL,
                temperature REAL,
                key_alias TEXT NOT NULL,
                local_only INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_provider_profiles_kind
                ON provider_profiles(kind)
            """)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS cluster_analysis_cache (
                id TEXT PRIMARY KEY NOT NULL,
                cluster_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                expires_at_rfc3339 TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_analysis_cache_cluster_expiry
                ON cluster_analysis_cache(cluster_id, expires_at_rfc3339)
            """)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS cluster_mutation_audit (
                id TEXT PRIMARY KEY NOT NULL,
                cluster_id TEXT NOT NULL,
                verb TEXT NOT NULL,
                gvk_group TEXT NOT NULL,
                gvk_version TEXT NOT NULL,
                gvk_kind TEXT NOT NULL,
                namespace TEXT,
                resource_name TEXT NOT NULL,
                manifest_digest TEXT NOT NULL,
                confirmation_token TEXT NOT NULL,
                confirmation_issued_at_seconds INTEGER NOT NULL,
                double_confirmed INTEGER NOT NULL DEFAULT 0,
                requested_at TEXT NOT NULL,
                response_resource_version TEXT,
                result TEXT NOT NULL,
                error_code TEXT,
                error_message TEXT,
                previous_entry_digest TEXT NOT NULL,
                entry_digest TEXT,
                key_version TEXT NOT NULL DEFAULT 'v1',
                chain_state TEXT NOT NULL DEFAULT 'intact'
            )
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_mutation_audit_cluster_time
                ON cluster_mutation_audit(cluster_id, requested_at)
            """)
    }
    // swiftlint:enable function_body_length
}
