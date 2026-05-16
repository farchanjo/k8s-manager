// Actors/PersistenceActor.swift — local_persistence bounded context
// DDD role: Domain Service (write-serialization gate, ADR-0010)
//
// `PersistenceActor` is the SINGLE write gate for all SQLite traffic in the
// local_persistence bounded context. Adapters call into it rather than
// touching GRDB directly. The domain core never imports GRDB; the abstraction
// is expressed through `PersistenceWriter` / `PersistenceReader`.
//
// ADR refs: ADR-0010 (storage design — single-writer WAL actor)
//           ADR-0026 (filesystem layout)

import Foundation

// MARK: - PersistenceReader

/// Capability for performing non-mutating database queries.
///
/// Implemented by `GRDBWriterAdapter` in the adapter layer; declared here so
/// the domain core never imports GRDB. All closures cross actor boundaries, so
/// the protocol inherits `Sendable`.
public protocol PersistenceReader: Sendable {
    /// Executes `work` inside a read transaction, returning its result.
    ///
    /// - Throws: Forwards any error thrown by `work`.
    func read<T: Sendable>(
        _ work: @Sendable (any DatabaseHandle) throws -> T
    ) throws -> T
}

// MARK: - PersistenceWriter

/// Capability for performing mutating database operations, and also for reads.
///
/// `PersistenceWriter` extends `PersistenceReader` so a single adapter can
/// satisfy both. The domain core never sees `DatabaseWriter` from GRDB.
public protocol PersistenceWriter: PersistenceReader {
    /// Executes `work` inside a write transaction, returning its result.
    ///
    /// Writes are serialized by the adapter's underlying serialization queue
    /// (GRDB WAL mode). Callers must not assume concurrent write access.
    ///
    /// - Throws: Forwards any error thrown by `work`.
    func write<T: Sendable>(
        _ work: @Sendable (any DatabaseHandle) throws -> T
    ) throws -> T

    /// Blocks the caller until all previously submitted writes have committed.
    ///
    /// Maps to GRDB's `barrierWriteWithoutTransaction` semantic: all writes
    /// enqueued before this call are drained before `barrier()` returns.
    func barrier() async
}

// MARK: - DatabaseHandle

/// Opaque handle to an open database connection.
///
/// The domain core calls adapter-vended functions that accept this handle;
/// those functions are defined by adapter-layer type-erased closures. The
/// domain core never inspects the concrete type behind this existential.
public protocol DatabaseHandle: Sendable {}

// MARK: - PersistenceActorError

/// Errors raised by `PersistenceActor`.
public enum PersistenceActorError: Error, Sendable {
    /// A read or write operation failed in the underlying adapter.
    case operationFailed(underlying: String)
}

// NOTE: `NullDatabaseHandle`, `UnimplementedPersistenceWriter`, and
// `FakePersistenceWriter` are declared in `Ports/Dependencies.swift` so that
// `PersistenceActorKey` (testValue/liveValue) can reference them without
// creating a separate file. They are NOT duplicated here.

// MARK: - PersistenceActor

/// Actor that serializes all SQLite write traffic for the
/// `local_persistence` bounded context.
///
/// Every adapter that mutates the database MUST route its writes through this
/// actor rather than calling GRDB directly. Reads may also be routed here for
/// consistency, though GRDB WAL mode permits concurrent readers.
///
/// The actor holds one `PersistenceWriter` that owns the underlying GRDB
/// `DatabaseWriter`. Construction is the composition root's responsibility
/// (typically `GRDBPersistenceAdapter.makePersistenceActor()`).
///
/// - Note: `GRDBWriterAdapter` — which wraps `DatabaseWriter` to satisfy
///   `PersistenceWriter` — lives in the adapter layer and is out of scope for
///   this file. The coordinator should add `GRDBWriterAdapter.swift` there.
public actor PersistenceActor {

    // MARK: State

    private let writer: any PersistenceWriter

    // MARK: Init

    /// Creates an actor that routes all database traffic through `writer`.
    ///
    /// - Parameter writer: An adapter-supplied `PersistenceWriter`. Must be
    ///   thread-safe internally (GRDB `DatabasePool` or `DatabaseQueue` both
    ///   satisfy this).
    public init(writer: any PersistenceWriter) {
        self.writer = writer
    }

    // MARK: Read

    /// Executes `work` inside a read transaction and returns the result.
    ///
    /// Concurrent read calls are permitted; GRDB WAL mode handles isolation.
    ///
    /// - Parameter work: A `@Sendable` closure receiving an opaque
    ///   `DatabaseHandle`. The closure runs synchronously on GRDB's reader pool.
    /// - Returns: The value produced by `work`.
    /// - Throws: `PersistenceActorError.operationFailed` wrapping the
    ///   underlying error message, or rethrows directly when the adapter
    ///   throws a typed error.
    public func read<T: Sendable>(
        _ work: @Sendable (any DatabaseHandle) throws -> T
    ) async throws -> T {
        try writer.read(work)
    }

    // MARK: Write

    /// Executes `work` inside a write transaction and returns the result.
    ///
    /// Writes are serialized; only one write transaction runs at a time.
    /// Callers MUST NOT call `write` re-entrantly from within a write closure.
    ///
    /// - Parameter work: A `@Sendable` closure receiving an opaque
    ///   `DatabaseHandle`. Mutations performed inside `work` are committed
    ///   atomically on success; rolled back on throw.
    /// - Returns: The value produced by `work`.
    /// - Throws: Rethrows errors from `work`.
    public func write<T: Sendable>(
        _ work: @Sendable (any DatabaseHandle) throws -> T
    ) async throws -> T {
        try writer.write(work)
    }

    // MARK: Barrier

    /// Waits for all in-flight write operations to commit before returning.
    ///
    /// Use this to establish a happens-before relationship — e.g. flush all
    /// pending writes before snapshotting state for a restoration manifest.
    ///
    /// Maps to GRDB's `barrierWriteWithoutTransaction` semantic on the
    /// underlying writer.
    public func barrier() async {
        await writer.barrier()
    }
}
