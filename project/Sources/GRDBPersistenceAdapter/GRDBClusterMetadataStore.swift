// GRDBClusterMetadataStore.swift — GRDBPersistenceAdapter
// DDD role: RepositoryImpl (secondary adapter — outbound to SQLite)
// Implements: ClusterMetadataStorePort (LocalPersistence)
// ADR refs: ADR-0010, cluster_intelligence bounded context

import Foundation
import GRDB
import LocalPersistence
import Logging

// MARK: - GRDBClusterMetadataStore

/// SQLite-backed implementation of ``ClusterMetadataStorePort``.
///
/// Provides TTL-bounded upsert/read/prune for LLM-generated cluster analyses.
public struct GRDBClusterMetadataStore: ClusterMetadataStorePort {

    private let db: any DatabaseWriter
    private let logger: Logger

    // MARK: Init

    public init(db: any DatabaseWriter, logger: Logger = .init(label: "grdb.cluster-cache")) {
        self.db = db
        self.logger = logger
    }

    // MARK: ClusterMetadataStorePort

    public func cachedAnalysis(
        clusterId: UUID,
        kind: AnalysisKind,
        now: Date
    ) async throws -> ClusterAnalysisCache? {
        let nowString = Self.iso8601(now)
        return try await db.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT * FROM cluster_analysis_cache
                    WHERE cluster_id = ? AND kind = ? AND expires_at_rfc3339 > ?
                    ORDER BY created_at DESC
                    LIMIT 1
                    """,
                arguments: [clusterId.uuidString, kind.rawValue, nowString]
            ) else { return nil }
            return analysisCache(from: row)
        }
    }

    public func upsertAnalysis(_ entry: ClusterAnalysisCache) async throws {
        do {
            try await db.write { database in
                // Delete any prior entry for the same (cluster_id, kind) pair.
                try database.execute(
                    sql: """
                        DELETE FROM cluster_analysis_cache
                        WHERE cluster_id = ? AND kind = ?
                        """,
                    arguments: [entry.clusterId.uuidString, entry.kind.rawValue]
                )
                try database.execute(
                    sql: """
                        INSERT INTO cluster_analysis_cache
                            (id, cluster_id, kind, payload_json, expires_at_rfc3339, created_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        entry.id.uuidString,
                        entry.clusterId.uuidString,
                        entry.kind.rawValue,
                        entry.payloadJSON,
                        Self.iso8601(entry.expiresAt),
                        Self.iso8601(entry.createdAt)
                    ]
                )
            }
        } catch {
            throw ClusterMetadataStoreError.storageError(underlying: error.localizedDescription)
        }
    }

    @discardableResult
    public func pruneExpired(now: Date) async throws -> Int {
        do {
            return try await db.write { database in
                try database.execute(
                    sql: "DELETE FROM cluster_analysis_cache WHERE expires_at_rfc3339 < ?",
                    arguments: [Self.iso8601(now)]
                )
                return database.changesCount
            }
        } catch {
            throw ClusterMetadataStoreError.storageError(underlying: error.localizedDescription)
        }
    }

    // MARK: Row mapping

    private func analysisCache(from row: Row) -> ClusterAnalysisCache {
        ClusterAnalysisCache(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            clusterId: UUID(uuidString: row["cluster_id"]) ?? UUID(),
            kind: AnalysisKind(rawValue: row["kind"]) ?? .clusterSummary,
            payloadJSON: row["payload_json"],
            expiresAt: Self.parseDate(row["expires_at_rfc3339"]),
            createdAt: Self.parseDate(row["created_at"])
        )
    }

    // MARK: Date helpers

    private static func iso8601Formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private static func iso8601(_ date: Date) -> String {
        Self.iso8601Formatter().string(from: date)
    }

    private static func parseDate(_ string: String) -> Date {
        Self.iso8601Formatter().date(from: string) ?? Date(timeIntervalSince1970: 0)
    }
}
