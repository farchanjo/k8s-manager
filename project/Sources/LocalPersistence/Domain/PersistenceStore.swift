// Domain/PersistenceStore.swift — local_persistence bounded context
// DDD role: AggregateRoot (the physical SQLite WAL store)
// CUE source: docs/arch/contexts/local_persistence/schemas/persistence_store.cue
// ADR refs: ADR-0010 (storage design), ADR-0026 (filesystem layout)

import Foundation

// MARK: - PersistenceStore

/// Aggregate root representing the single durable SQLite WAL store managed by
/// the `local_persistence` bounded context.
///
/// Mirrors `#PersistenceStore` from `persistence_store.cue`.
///
/// Physical path: `~/.config/k8smanager/storage.sqlite3` (ADR-0026).
/// PRAGMAs applied after every connection open:
/// ```
/// PRAGMA journal_mode=WAL;
/// PRAGMA synchronous=NORMAL;
/// PRAGMA foreign_keys=ON;
/// PRAGMA busy_timeout=5000;
/// PRAGMA cache_size=-65536;
/// ```
///
/// The domain core never imports GRDB; all PRAGMA logic lives in
/// `GRDBPersistenceAdapter`.
public struct PersistenceStore: Hashable, Sendable, Codable {
    /// UUIDv7 generated on first launch. Persisted in `operator_preferences`
    /// under key `"store.aggregate_id"`. Survives restarts.
    public let id: UUID

    /// Absolute POSIX path to the SQLite file.
    ///
    /// Must satisfy `^/.+` (no relative paths, no UNC paths).
    public let storageFilePath: String

    /// Always `"wal"`. Attempting to open the store with a different journal
    /// mode is a logic error.
    public let journalMode: String

    /// The highest applied migration version, read from `schema_migrations` at
    /// startup. Must be `>= 1` after the baseline migration has run.
    public let schemaVersion: Int

    /// RFC 3339 UTC timestamp of the most recent `VACUUM INTO` run.
    /// `nil` until the first scheduled vacuum executes.
    public let lastVacuumAt: Date?

    public init(
        id: UUID,
        storageFilePath: String,
        schemaVersion: Int,
        lastVacuumAt: Date? = nil
    ) {
        self.id = id
        self.storageFilePath = storageFilePath
        self.journalMode = "wal"
        self.schemaVersion = schemaVersion
        self.lastVacuumAt = lastVacuumAt
    }
}

// MARK: - PersistenceStore invariant checks

public extension PersistenceStore {
    /// Returns `true` when all CUE-declared invariants hold.
    var isValid: Bool {
        storageFilePath.hasPrefix("/")
            && schemaVersion >= 1
            && journalMode == "wal"
    }
}

// MARK: - PersistenceMigration

/// Entity recording a single applied schema migration.
///
/// Mirrors `#PersistenceMigration` from `persistence_store.cue`.
/// Rows in `schema_migrations` are the persistence projection of this entity.
public struct PersistenceMigration: Hashable, Sendable, Codable {
    /// Strictly monotonic migration number starting at 1.
    public let version: Int

    /// UTC timestamp at which the migration completed.
    public let appliedAt: Date

    /// Short human-readable summary matching the Swift function name
    /// (e.g. `"v1_initial_schema"`).
    public let description: String

    /// SHA-256 hex digest of the migration SQL file.
    ///
    /// Must satisfy `^[0-9a-f]{64}$`.
    public let checksumSHA256: String

    public init(
        version: Int,
        appliedAt: Date,
        description: String,
        checksumSHA256: String
    ) {
        self.version = version
        self.appliedAt = appliedAt
        self.description = description
        self.checksumSHA256 = checksumSHA256
    }
}

// MARK: - PersistenceMigration invariant checks

public extension PersistenceMigration {
    /// Returns `true` when all CUE-declared invariants hold.
    var isValid: Bool {
        version >= 1
            && !description.isEmpty
            && checksumSHA256.count == 64
            && checksumSHA256.allSatisfy { $0.isHexDigit }
    }
}
