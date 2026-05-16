// ViewModels/MetricsObservabilityViewModel.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states)

import Foundation
import Dependencies
import Logging
import MetricsObservability
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.metrics_observability")

// MARK: - MetricsObservabilityViewModel

/// View model for the metrics and observability screen.
///
/// Owned by `MetricsObservabilityView`. Drives Prometheus endpoint discovery
/// and curated PromQL query execution. All mutations are `@MainActor`-isolated
/// so SwiftUI observation coalesces updates without data races.
@Observable
@MainActor
public final class MetricsObservabilityViewModel {

    // MARK: State

    /// Lifecycle state of the endpoint discovery operation.
    public var endpoints: AsyncResource<[PrometheusEndpoint]> = .idle

    /// Per-query result state, keyed by `CuratedQuery.id`.
    public var queryResults: [String: AsyncResource<PromQueryResult>] = [:]

    /// Currently selected query from the catalog picker.
    public var selectedQuery: CuratedQuery? = CuratedQueryCatalog.all.first

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.prometheusQuery) private var prometheusQuery

    @ObservationIgnored
    @Dependency(\.endpointDiscovery) private var endpointDiscovery

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Discovers Prometheus endpoints for all available Kubernetes contexts.
    ///
    /// Uses a fixed placeholder context ID; production callers should pass the
    /// active context ID from `ContextNavigation`.
    public func discoverEndpoints() async {
        endpoints = .loading
        log.info("discoverEndpoints start")
        do {
            let contextId = UUID()
            let found = try await endpointDiscovery.discover(kubernetesContextId: contextId)
            log.info("discoverEndpoints OK — count=\(found.count)")
            endpoints = .success(found)
        } catch {
            log.error("discoverEndpoints FAILED — \(error)")
            endpoints = .failure(error)
        }
    }

    /// Executes a curated query against the first healthy discovered endpoint.
    ///
    /// - Parameter query: The catalog entry to execute.
    public func runCuratedQuery(_ query: CuratedQuery) async {
        queryResults[query.id] = .loading
        log.info("runCuratedQuery start id=\(query.id) category=\(query.category.rawValue)")
        do {
            let endpoint = try resolveEndpoint()
            let promQuery = PromQuery.instant(expr: query.expr)
            let result = try await prometheusQuery.instantQuery(promQuery, endpoint: endpoint)
            log.info("runCuratedQuery OK id=\(query.id)")
            queryResults[query.id] = .success(result)
        } catch {
            log.error("runCuratedQuery FAILED id=\(query.id) — \(error)")
            queryResults[query.id] = .failure(error)
        }
    }

    // MARK: Private helpers

    /// Returns the first healthy endpoint or the first available one.
    ///
    /// - Throws: `EndpointDiscoveryError.unimplemented` when no endpoints are known.
    private func resolveEndpoint() throws -> PrometheusEndpoint {
        guard let list = endpoints.value, !list.isEmpty else {
            throw EndpointDiscoveryError.kubernetesApiUnavailable(
                detail: "No endpoints discovered. Run discovery first."
            )
        }
        return list.first { $0.status == .healthy } ?? list[0]
    }
}
