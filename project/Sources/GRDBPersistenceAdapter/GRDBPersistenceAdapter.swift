// GRDBPersistenceAdapter.swift — infrastructure adapter placeholder
// Implements: PersistencePort from LocalPersistence
// Library: groue/GRDB.swift@6.29+ (Tier A per ADR-0019)
// Status: skeleton; port implementations pending domain ports definition.
import GRDB
import LocalPersistence
import Foundation

/// Namespace marker for the GRDBPersistenceAdapter adapter target.
///
/// Concrete actor types implementing the domain ports land under this enum
/// in subsequent rounds. This file exists so the target compiles cleanly
/// under Swift 6 strict concurrency with the imported infrastructure library.
public enum GRDBPersistenceAdapter: Sendable {
    public static let moduleVersion = "0.0.1-skeleton"
}
