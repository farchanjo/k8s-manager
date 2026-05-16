// Ports/ClusterMetadataStorePort.swift — local_persistence bounded context
// DDD role: Port (secondary — outbound to persistence infrastructure)
// Consumed by: assistant_chat, cluster_intelligence bounded contexts
// Narrative ref: domain/narrative.md §Tactical roles
// DBML ref: storage.dbml §cluster_analysis_cache

import Foundation
import SharedKernel

// MARK: - AnalysisKind

/// Discriminant for cluster-analysis cache entries.
///
/// Mirrors the `kind` column constraint in `storage.dbml`.
public enum AnalysisKind: String, Hashable, Sendable, Codable {
    case clusterSummary     = "cluster_summary"
    case nodePressure       = "node_pressure"
    case rolloutHistory     = "rollout_history"
    case workloadTopology   = "workload_topology"
    case recentEventsDigest = "recent_events_digest"
}

// MARK: - ClusterAnalysisCache

/// A single TTL-bounded cache entry for an LLM-generated cluster analysis.
public struct ClusterAnalysisCache: Hashable, Sendable, Codable {
    public let id: UUID
    /// UUIDv7 of the target cluster.
    public let clusterId: UUID
    public let kind: AnalysisKind
    /// Full JSON payload produced by the intelligence analysis step.
    public let payloadJSON: String
    /// Rows past this date are eligible for pruning by the vacuum task.
    public let expiresAt: Date
    public let createdAt: Date

    public init(
        id: UUID,
        clusterId: UUID,
        kind: AnalysisKind,
        payloadJSON: String,
        expiresAt: Date,
        createdAt: Date
    ) {
        self.id = id
        self.clusterId = clusterId
        self.kind = kind
        self.payloadJSON = payloadJSON
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }
}

// MARK: - ClusterMetadataStoreError

/// Errors raised by `ClusterMetadataStorePort` implementations.
public enum ClusterMetadataStoreError: Error, Sendable {
    /// No cache entry exists for the given identifiers.
    case entryNotFound(clusterId: UUID, kind: AnalysisKind)
    /// The underlying persistence layer returned an error.
    case storageError(underlying: String)
    /// The port has not been registered in this process.
    case unimplemented
}

// MARK: - ClusterMetadataStorePort

/// Port for reading and writing the cluster-analysis TTL cache.
///
/// Declared in the domain core; implemented by `GRDBPersistenceAdapter`.
public protocol ClusterMetadataStorePort: Sendable {
    /// Returns the non-expired cache entry for `(clusterId, kind)`, or `nil`
    /// when absent or expired.
    func cachedAnalysis(
        clusterId: UUID,
        kind: AnalysisKind,
        now: Date
    ) async throws -> ClusterAnalysisCache?

    /// Upserts a cache entry.
    ///
    /// If a prior entry for the same `(clusterId, kind)` pair exists, it is
    /// replaced.
    func upsertAnalysis(_ entry: ClusterAnalysisCache) async throws

    /// Prunes all rows where `expiresAt < now`. Returns the count of deleted
    /// rows.
    @discardableResult
    func pruneExpired(now: Date) async throws -> Int
}

// MARK: - UnimplementedClusterMetadataStorePort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedClusterMetadataStorePort: ClusterMetadataStorePort {
    public init() {}

    public func cachedAnalysis(
        clusterId: UUID,
        kind: AnalysisKind,
        now: Date
    ) async throws -> ClusterAnalysisCache? {
        throw ClusterMetadataStoreError.unimplemented
    }

    public func upsertAnalysis(_ entry: ClusterAnalysisCache) async throws {
        throw ClusterMetadataStoreError.unimplemented
    }

    public func pruneExpired(now: Date) async throws -> Int {
        throw ClusterMetadataStoreError.unimplemented
    }
}
