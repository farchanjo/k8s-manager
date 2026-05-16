// GRDBWriterAdapter.swift — GRDBPersistenceAdapter
// DDD role: InfrastructureAdapter (bridges GRDB DatabaseWriter to LocalPersistence protocols)
// ADR refs: ADR-0010 (single-writer WAL actor), ADR-0026 (filesystem layout)

import Foundation
import GRDB
import LocalPersistence

// MARK: - GRDBWriterAdapter

/// Adapts a GRDB `DatabaseWriter` to satisfy `PersistenceWriter` and
/// `PersistenceReader` so `PersistenceActor` never imports GRDB directly.
///
/// Both `DatabaseQueue` and `DatabasePool` conform to `DatabaseWriter`, so
/// either backend is accepted without changes here.
///
/// `@unchecked Sendable` is justified: GRDB's `DatabaseWriter` protocol is
/// documented as thread-safe; all mutable state is owned by GRDB's internal
/// serialization queue.
public struct GRDBWriterAdapter: PersistenceWriter, PersistenceReader, @unchecked Sendable {

    // MARK: State

    private let dbWriter: any DatabaseWriter

    // MARK: Init

    /// Creates an adapter wrapping `writer`.
    ///
    /// - Parameter writer: A GRDB `DatabaseWriter` — either `DatabaseQueue` or
    ///   `DatabasePool` — already configured and migrated.
    public init(writer: any DatabaseWriter) {
        self.dbWriter = writer
    }

    // MARK: PersistenceReader

    /// Executes `work` inside a GRDB read transaction, returning its result.
    ///
    /// Maps directly to `DatabaseWriter.read(_:)`. The closure runs on GRDB's
    /// reader pool; for `DatabaseQueue` that is the single serial queue.
    ///
    /// - Parameter work: A `@Sendable` closure receiving an opaque
    ///   `GRDBDatabaseHandle`. The handle is valid only for the duration of
    ///   the closure.
    /// - Returns: The value produced by `work`.
    /// - Throws: Forwards any error thrown by `work` or GRDB internals.
    public func read<T: Sendable>(
        _ work: @Sendable (any DatabaseHandle) throws -> T
    ) throws -> T {
        try dbWriter.read { db in
            try work(GRDBDatabaseHandle(db: db))
        }
    }

    // MARK: PersistenceWriter

    /// Executes `work` inside a GRDB write transaction, returning its result.
    ///
    /// Maps to `DatabaseWriter.write(_:)`. GRDB serialises concurrent writes;
    /// the transaction is committed on success and rolled back on throw.
    ///
    /// - Parameter work: A `@Sendable` closure receiving an opaque
    ///   `GRDBDatabaseHandle`. Mutations are visible outside the closure only
    ///   after this method returns successfully.
    /// - Returns: The value produced by `work`.
    /// - Throws: Forwards any error thrown by `work` or GRDB internals.
    public func write<T: Sendable>(
        _ work: @Sendable (any DatabaseHandle) throws -> T
    ) throws -> T {
        try dbWriter.write { db in
            try work(GRDBDatabaseHandle(db: db))
        }
    }

    /// Blocks the caller until all previously enqueued writes have committed.
    ///
    /// Dispatches a no-op write through GRDB's serial writer queue, which
    /// provides the happens-before guarantee required by
    /// `PersistenceActor.barrier()`. For `DatabaseQueue` this is equivalent to
    /// waiting for the queue to drain; for `DatabasePool` it drains the writer.
    public func barrier() async {
        _ = try? await dbWriter.write { _ in }
    }
}

// MARK: - GRDBDatabaseHandle

/// Opaque wrapper around a live GRDB `Database` connection, satisfying the
/// `DatabaseHandle` marker protocol declared in `LocalPersistence`.
///
/// The domain core never inspects the concrete type — it receives the
/// existential `any DatabaseHandle` and passes it to adapter-layer closures
/// that downcast to `GRDBDatabaseHandle` when they need `db` directly.
///
/// `@unchecked Sendable`: `Database` is not `Sendable`, but instances of
/// this type are only ever created inside GRDB callbacks and must not
/// escape those callbacks. The constraint is upheld by usage convention,
/// not by the type system.
struct GRDBDatabaseHandle: DatabaseHandle, @unchecked Sendable {

    // MARK: State

    /// The live GRDB database connection. Adapter-layer closures that receive
    /// `any DatabaseHandle` may downcast to `GRDBDatabaseHandle` to access `db`.
    let db: Database
}
