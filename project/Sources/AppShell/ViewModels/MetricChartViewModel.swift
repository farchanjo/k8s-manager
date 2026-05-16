// ViewModels/MetricChartViewModel.swift — app_shell bounded context
// DDD role: ViewModel — Prometheus drawer chart
// ADR ref: ADR-0058 (drawer chart, cadence ceiling, cancel on close)
// ADR ref: ADR-0016 (curated queries, downsampling)
// ADR ref: ADR-0044 (injection prevention — delegated to PrometheusQueryPort)

import Foundation
import Logging
import Observation
import Dependencies
import MetricsObservability
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.metric_chart")

// MARK: - PrometheusEndpointStatus

/// Reflects the availability state of the Prometheus endpoint for the
/// active cluster. Drives the no-Prometheus fallback in the drawer.
public enum PrometheusEndpointStatus: Sendable {
    /// No endpoint configured for this cluster.
    case notConfigured
    /// Discovery pipeline is running.
    case discovering
    /// Last probe returned a non-OK status.
    case unreachable
    /// A healthy endpoint is available.
    case available(PrometheusEndpoint)
}

// MARK: - MetricChartLoadState

/// Loading state for a single chart series.
public enum MetricChartLoadState: Sendable {
    case idle
    case loading
    case loaded([MetricPoint])
    case failed(String)
}

// MARK: - MetricChartViewModel

/// View model for the Prometheus chart embedded in the resource detail drawer.
///
/// Subscribes to `PrometheusQueryPort` (via DI), enforces the ADR-0058
/// 15-second cadence ceiling per `(endpointId, queryId)` pair, and cancels
/// all in-flight query tasks when the drawer closes.
///
/// The view model is @Observable so SwiftUI auto-tracks property access
/// without `@Published` wrappers (iOS 17+ / macOS 14+ requirement).
@Observable
@MainActor
public final class MetricChartViewModel {

    // MARK: Published state

    /// Endpoint availability for the active cluster.
    public var endpointStatus: PrometheusEndpointStatus = .notConfigured

    /// Selected time range (drives query re-issue on change).
    public var timeRange: MetricTimeRange = .oneHour

    /// Active series key selection (drives query re-issue on change).
    public var selectedSeries: Set<MetricSeriesKey> = []

    /// Per-series load state keyed by `MetricSeriesKey.rawValue`.
    public var seriesState: [String: MetricChartLoadState] = [:]

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.prometheusQuery) private var queryPort

    // MARK: Private state

    @ObservationIgnored
    private var activeTasks: [String: Task<Void, Never>] = [:]

    /// Last query timestamp per `queryId` for the 15-second cadence ceiling.
    @ObservationIgnored
    private var lastQueryAt: [String: Date] = [:]

    /// Minimum interval between queries per `(endpointId, queryId)` — ADR-0058.
    @ObservationIgnored
    private var cadenceCeilingSeconds: TimeInterval = 15

    // MARK: Init

    /// Creates the view model with an optional custom cadence ceiling for testing.
    ///
    /// - Parameter cadenceCeilingSeconds: Minimum seconds between queries for
    ///   the same `(endpointId, queryId)` pair. Default is 15 (ADR-0058).
    public init(cadenceCeilingSeconds: TimeInterval = 15) {
        self.cadenceCeilingSeconds = cadenceCeilingSeconds
    }

    // MARK: Lifecycle

    /// Configures the view model for `ref` and starts fetching.
    ///
    /// Call this once when the drawer opens. Cancels any previous tasks.
    ///
    /// - Parameters:
    ///   - ref: The resource for which to display charts.
    ///   - endpoint: The resolved Prometheus endpoint for the active cluster.
    public func start(ref: ResourceRef, endpoint: PrometheusEndpoint) {
        endpointStatus = .available(endpoint)
        selectedSeries = DrawerChartCatalog.defaultSelection(for: ref.kind.kind)
        fetchAll(ref: ref, endpoint: endpoint)
    }

    /// Called when no Prometheus endpoint is configured.
    public func markNotConfigured() {
        endpointStatus = .notConfigured
        cancelAll()
    }

    /// Called when the discovery pipeline is running.
    public func markDiscovering() {
        endpointStatus = .discovering
    }

    /// Called when the last health probe failed.
    public func markUnreachable() {
        endpointStatus = .unreachable
        cancelAll()
    }

    /// Cancels all in-flight tasks. Call when the drawer closes.
    public func cancelAll() {
        for (_, task) in activeTasks { task.cancel() }
        activeTasks.removeAll()
        log.info("MetricChartViewModel: all query tasks cancelled")
    }

    /// Reissues all active series queries (called on time-range or series change).
    ///
    /// - Parameters:
    ///   - ref: The resource reference.
    ///   - endpoint: Prometheus endpoint to query.
    public func refresh(ref: ResourceRef, endpoint: PrometheusEndpoint) {
        cancelAll()
        lastQueryAt.removeAll()
        fetchAll(ref: ref, endpoint: endpoint)
    }

    // MARK: Private

    private func fetchAll(ref: ResourceRef, endpoint: PrometheusEndpoint) {
        let kind = ref.kind.kind
        let cpuSpecs = DrawerChartCatalog.cpuSeries(for: kind)
        let memSpecs = DrawerChartCatalog.memorySeries(for: kind)
        let allSpecs = cpuSpecs + memSpecs

        for spec in allSpecs where selectedSeries.contains(spec.key) {
            launchFetch(spec: spec, ref: ref, endpoint: endpoint)
        }
    }

    private func launchFetch(
        spec: ChartSeriesSpec,
        ref: ResourceRef,
        endpoint: PrometheusEndpoint
    ) {
        let queryId = spec.key.rawValue
        if !cadenceAllows(queryId: queryId, endpointId: endpoint.id) {
            log.debug("cadence ceiling active for queryId=\(queryId) — skipping")
            return
        }

        seriesState[queryId] = .loading

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let expr = substituteParams(spec.expr, ref: ref)
                let range = buildTimeRange()
                let query = PromQuery.range(expr: expr, range: range)
                let result = try await queryPort.rangeQuery(query, endpoint: endpoint)
                let points = Self.extractPoints(from: result)
                await MainActor.run {
                    self.seriesState[queryId] = .loaded(points)
                    self.lastQueryAt[queryId] = Date()
                    log.info("MetricChartViewModel: fetched queryId=\(queryId) points=\(points.count)")
                }
            } catch is CancellationError {
                log.debug("MetricChartViewModel: task cancelled queryId=\(queryId)")
            } catch {
                await MainActor.run {
                    self.seriesState[queryId] = .failed(error.localizedDescription)
                    log.warning("MetricChartViewModel: fetch failed queryId=\(queryId) — \(error)")
                }
            }
        }
        activeTasks[queryId] = task
    }

    /// Returns `true` when at least `cadenceCeilingSeconds` have elapsed since
    /// the last completed query for `(endpointId, queryId)` — ADR-0058.
    private func cadenceAllows(queryId: String, endpointId: UUID) -> Bool {
        let key = "\(endpointId.uuidString)-\(queryId)"
        guard let last = lastQueryAt[key] else { return true }
        return Date().timeIntervalSince(last) >= cadenceCeilingSeconds
    }

    private func buildTimeRange() -> TimeRange {
        let now = Date()
        let start = now.addingTimeInterval(-Double(timeRange.seconds))
        let fmt = ISO8601DateFormatter()
        return TimeRange(
            start: fmt.string(from: start),
            end: fmt.string(from: now),
            stepSeconds: timeRange.stepSeconds
        )
    }

    /// Substitutes `{namespace}`, `{pod}`, `{node}`, `{workload}` placeholders.
    ///
    /// Values are NOT sanitized here — validation is performed by the
    /// `PrometheusQueryPort` implementation (ADR-0044 injection guard).
    private func substituteParams(_ expr: String, ref: ResourceRef) -> String {
        var result = expr
        result = result.replacingOccurrences(of: "{namespace}", with: ref.namespace ?? "")
        result = result.replacingOccurrences(of: "{pod}", with: ref.name)
        result = result.replacingOccurrences(of: "{node}", with: ref.name)
        result = result.replacingOccurrences(of: "{workload}", with: ref.name)
        return result
    }

    private static func extractPoints(from result: PromQueryResult) -> [MetricPoint] {
        guard case .rangeMatrix(let series) = result,
              let first = series.first else { return [] }
        return first.points.map { MetricPoint(tUnix: $0.tUnix, value: $0.value) }
    }
}
