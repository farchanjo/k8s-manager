// GRDBPersistenceAdapter.swift — GRDBPersistenceAdapter
// DDD role: CompositionRoot (public facade)
// ADR refs: ADR-0010, ADR-0026
import Foundation
import GRDB
import LocalPersistence
import MetricsObservability
import TerminalSession
import Logging

// MARK: - GRDBPersistenceAdapter

/// Public facade for the GRDB-backed persistence layer.
///
/// Call ``openBundle(at:keyProvider:logger:)`` once at startup and wire the
/// returned ``PersistenceBundle`` into the dependency-injection container.
public enum GRDBPersistenceAdapter: Sendable {

    // MARK: - PersistenceBundle

    /// All five GRDB repository adapters wired to the same `DatabaseQueue`.
    ///
    /// The bundle owns the `DatabaseQueue` lifecycle. Pass individual properties
    /// into `prepareDependencies { }` at the composition root.
    public struct PersistenceBundle: Sendable {
        /// Repository for chat sessions and messages.
        public let chatRepository: GRDBChatRepository
        /// Repository for LLM provider profiles.
        public let providerRepository: GRDBProviderRepository
        /// TTL cache for LLM-generated cluster analyses.
        public let clusterMetadataStore: GRDBClusterMetadataStore
        /// Append-only HMAC-gated mutation audit chain.
        public let auditChainStore: GRDBAuditChainStore
        /// Repository for terminal session metadata (ADR-0017).
        public let terminalRepository: GRDBTerminalRepository
        /// Append-only HMAC-gated secret-reveal audit (ADR-0063).
        public let secretRevealAudit: GRDBSecretRevealAudit
        /// GRDB-backed Prometheus endpoint config store (ADR-0016).
        public let prometheusEndpointRepository: GRDBPrometheusEndpointRepository
    }

    // MARK: - Factory

    /// Opens (creating if absent) the SQLite file at `path`, runs all pending
    /// migrations via ``SchemaMigrator``, and returns a ``PersistenceBundle``
    /// whose adapters share the underlying `DatabaseQueue`.
    ///
    /// - Parameters:
    ///   - path: Absolute POSIX path to the `.sqlite3` file.
    ///   - keyProvider: HMAC key closure injected into ``GRDBAuditChainStore``.
    ///   - logger: Diagnostics destination for migration-progress messages.
    public static func openBundle(
        at path: String,
        keyProvider: @escaping KeyProvider,
        logger: Logger = Logger(label: "GRDBPersistenceAdapter")
    ) throws -> PersistenceBundle {
        let db = try SchemaMigrator.makeQueue(at: path, logger: logger)
        return PersistenceBundle(
            chatRepository: GRDBChatRepository(db: db),
            providerRepository: GRDBProviderRepository(db: db),
            clusterMetadataStore: GRDBClusterMetadataStore(db: db),
            auditChainStore: GRDBAuditChainStore(db: db, keyProvider: keyProvider),
            terminalRepository: GRDBTerminalRepository(db: db),
            secretRevealAudit: GRDBSecretRevealAudit(db: db, keyProvider: keyProvider),
            prometheusEndpointRepository: GRDBPrometheusEndpointRepository(db: db)
        )
    }
}
