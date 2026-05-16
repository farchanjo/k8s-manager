// GRDBPrometheusEndpointRepository.swift — GRDBPersistenceAdapter
// DDD role: Adapter (outbound — PrometheusEndpointRepositoryPort implementation)
// ADR refs: ADR-0010 (GRDB WAL persistence), ADR-0016 (Prometheus endpoint lifecycle)

import Foundation
import GRDB
import MetricsObservability

// MARK: - GRDBPrometheusEndpointRepository

/// SQLite-backed implementation of ``PrometheusEndpointRepositoryPort``.
///
/// Each `PrometheusEndpoint` aggregate is stored as a single row in the
/// `prometheus_endpoint` table (v5 migration). `save(_:)` uses GRDB
/// insert-or-replace semantics so repeated calls are idempotent for the same
/// `id`. `load()` returns all rows sorted by `kubernetes_context_id` then
/// `url` to give callers a stable, deterministic ordering.
///
/// `AuthStrategy` is persisted as a JSON blob because it is a Swift enum with
/// associated values. `DiscoverySource` and `EndpointStatus` are persisted as
/// their raw `String` values.
public struct GRDBPrometheusEndpointRepository: PrometheusEndpointRepositoryPort {

    // MARK: Properties

    private let db: any DatabaseWriter

    // MARK: Init

    /// Designated initialiser.
    ///
    /// - Parameter db: The shared `DatabaseWriter` (WAL-mode `DatabaseQueue`)
    ///   opened by `SchemaMigrator.makeQueue`.
    public init(db: any DatabaseWriter) {
        self.db = db
    }

    // MARK: PrometheusEndpointRepositoryPort

    public func save(_ endpoints: [PrometheusEndpoint]) async throws {
        do {
            try await db.write { database in
                for endpoint in endpoints {
                    let row = try Self.encode(endpoint)
                    try database.execute(
                        sql: """
                        INSERT INTO prometheus_endpoint (
                            id, kubernetes_context_id, url,
                            discovery_source, auth_strategy_json,
                            insecure_skip_tls_verify, status,
                            last_probed_at, version
                        ) VALUES (
                            :id, :kubernetes_context_id, :url,
                            :discovery_source, :auth_strategy_json,
                            :insecure_skip_tls_verify, :status,
                            :last_probed_at, :version
                        )
                        ON CONFLICT(id) DO UPDATE SET
                            kubernetes_context_id = excluded.kubernetes_context_id,
                            url                   = excluded.url,
                            discovery_source      = excluded.discovery_source,
                            auth_strategy_json    = excluded.auth_strategy_json,
                            insecure_skip_tls_verify = excluded.insecure_skip_tls_verify,
                            status                = excluded.status,
                            last_probed_at        = excluded.last_probed_at,
                            version               = excluded.version
                        """,
                        arguments: row
                    )
                }
            }
        } catch {
            throw PrometheusEndpointRepositoryError.persistenceFailure(
                detail: "save failed: \(error)"
            )
        }
    }

    public func load() async throws -> [PrometheusEndpoint] {
        do {
            return try await db.read { database in
                let rows = try Row.fetchAll(
                    database,
                    sql: """
                    SELECT id, kubernetes_context_id, url,
                           discovery_source, auth_strategy_json,
                           insecure_skip_tls_verify, status,
                           last_probed_at, version
                    FROM prometheus_endpoint
                    ORDER BY kubernetes_context_id ASC, url ASC
                    """
                )
                return try rows.map { try Self.decode($0) }
            }
        } catch let error as PrometheusEndpointRepositoryError {
            throw error
        } catch {
            throw PrometheusEndpointRepositoryError.persistenceFailure(
                detail: "load failed: \(error)"
            )
        }
    }

    // MARK: Private — encode / decode

    private static func encode(
        _ endpoint: PrometheusEndpoint
    ) throws -> StatementArguments {
        let authJSON = try JSONEncoder().encode(endpoint.authStrategy)
        guard let authString = String(data: authJSON, encoding: .utf8) else {
            throw PrometheusEndpointRepositoryError.persistenceFailure(
                detail: "auth_strategy JSON encoding produced non-UTF-8 bytes"
            )
        }
        // GRDB named-argument init requires (String, (any DatabaseValueConvertible)?) pairs.
        let pairs: [(String, (any DatabaseValueConvertible)?)] = [
            ("id", endpoint.id.uuidString),
            ("kubernetes_context_id", endpoint.kubernetesContextId.uuidString),
            ("url", endpoint.url),
            ("discovery_source", endpoint.discoverySource.rawValue),
            ("auth_strategy_json", authString),
            ("insecure_skip_tls_verify", endpoint.insecureSkipTLSVerify ? 1 : 0),
            ("status", endpoint.status.rawValue),
            ("last_probed_at", endpoint.lastProbedAt),
            ("version", endpoint.version),
        ]
        return StatementArguments(pairs)
    }

    private static func decode(_ row: Row) throws -> PrometheusEndpoint {
        guard
            let idString = row["id"] as? String,
            let id = UUID(uuidString: idString),
            let ctxString = row["kubernetes_context_id"] as? String,
            let contextId = UUID(uuidString: ctxString),
            let url = row["url"] as? String,
            let sourceRaw = row["discovery_source"] as? String,
            let source = DiscoverySource(rawValue: sourceRaw),
            let authJSON = row["auth_strategy_json"] as? String,
            let authData = authJSON.data(using: .utf8),
            let statusRaw = row["status"] as? String,
            let status = EndpointStatus(rawValue: statusRaw)
        else {
            throw PrometheusEndpointRepositoryError.persistenceFailure(
                detail: "decode: malformed row — required columns missing or invalid"
            )
        }
        let auth = try JSONDecoder().decode(AuthStrategy.self, from: authData)
        let insecure = (row["insecure_skip_tls_verify"] as? Int64 ?? 0) != 0
        return PrometheusEndpoint(
            id: id,
            kubernetesContextId: contextId,
            url: url,
            discoverySource: source,
            authStrategy: auth,
            insecureSkipTLSVerify: insecure,
            status: status,
            lastProbedAt: row["last_probed_at"] as? String,
            version: row["version"] as? String
        )
    }
}
