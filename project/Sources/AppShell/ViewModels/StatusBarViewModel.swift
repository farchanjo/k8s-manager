// ViewModels/StatusBarViewModel.swift — app_shell bounded context
// DDD role: ViewModel (reads from ClusterConnectivity + MetricsObservability ports)
// ADR ref: ADR-0051 (status bar telemetry — cluster identity, capacity, watches, errors)

import ClusterConnectivity
import Dependencies
import Foundation
import MetricsObservability
import SharedKernel
import SwiftUI

// MARK: - ErrorEntry

/// Timestamped record stored in the 5-minute in-memory ring buffer.
private struct ErrorEntry: Sendable {
    let date: Date
}

// MARK: - StatusBarViewModel

/// View model powering the 24 pt bottom status bar chrome strip.
///
/// Aggregates:
/// - Active cluster identity and connection state from `KubernetesApiPort`.
/// - CPU / Mem cluster-aggregate percentages from `PrometheusQueryPort` (optional).
/// - Active watch count (Wave 1: always 0; real value deferred to `WatchStreamCoordinator`).
/// - Error count from `.error` severity toasts within the last 5 minutes.
///
/// All mutations are confined to `@MainActor`. The 30 s refresh loop runs via structured `Task`.
@MainActor
@Observable
public final class StatusBarViewModel {

    // MARK: - ConnectionBadge

    /// Discrete visual state for the cluster connection indicator dot.
    public enum ConnectionBadge: String, Sendable {
        case connected
        case reconnecting
        case degraded
        case disconnected
        case unknown

        /// Unicode fill glyph for the status symbol.
        public var symbol: String {
            switch self {
            case .connected:    "●"
            case .reconnecting: "◐"
            case .degraded:     "◑"
            case .disconnected: "○"
            case .unknown:      "?"
            }
        }

        /// SwiftUI semantic color for the indicator dot.
        public var color: Color {
            switch self {
            case .connected:    .green
            case .reconnecting: .yellow
            case .degraded:     .orange
            case .disconnected: .red
            case .unknown:      .gray
            }
        }

        /// Maps a domain `HealthState` to the appropriate badge variant.
        public init(from state: HealthState) {
            switch state {
            case .reachable:    self = .connected
            case .degraded:     self = .degraded
            case .unreachable:  self = .disconnected
            case .unauthorized: self = .disconnected
            case .forbidden:    self = .degraded
            case .unknown:      self = .unknown
            }
        }
    }

    // MARK: - Published state

    /// Display name of the currently active cluster context.
    public var clusterName: String = "—"

    /// Kubernetes server version string (e.g. `"v1.31.2"`).
    public var serverVersion: String = "—"

    /// Connection state badge derived from the last health probe.
    public var connectionBadge: ConnectionBadge = .unknown

    /// Cluster-aggregate CPU utilisation percentage, or `nil` when unavailable.
    public var cpuPercent: Double? = nil

    /// Cluster-aggregate memory utilisation percentage, or `nil` when unavailable.
    public var memPercent: Double? = nil

    /// Count of active Kubernetes watch streams (Wave 1: always 0).
    public var activeWatchCount: Int = 0

    /// Count of error-severity events within the last 5 minutes.
    public var errorCount: Int = 0

    // MARK: - Dependencies

    @ObservationIgnored
    @Dependency(\.kubeconfigLoader) private var kubeconfigLoader

    @ObservationIgnored
    @Dependency(\.kubernetesApi) private var kubernetesApi

    @ObservationIgnored
    @Dependency(\.prometheusQuery) private var prometheusQuery

    @ObservationIgnored
    @Dependency(\.endpointDiscovery) private var endpointDiscovery

    // MARK: - Private state

    /// Ring buffer of error-severity toast timestamps.
    @ObservationIgnored
    private var errorRing: [ErrorEntry] = []

    /// Last resolved active cluster identifier.
    @ObservationIgnored
    private var activeClusterId: ClusterId?

    private static let errorWindowSeconds: Double = 300  // 5 min

    // MARK: - Init

    public init() {}

    // MARK: - Lifecycle

    /// Starts the 30 s refresh loop. Attach via `.task { await viewModel.start() }`.
    public func start() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    // MARK: - Public intent

    /// Performs a single synchronous refresh of all status bar fields.
    public func refresh() async {
        await fetchClusterInfo()
        await fetchClusterCapacity()
        pruneErrorRing(now: Date())
        errorCount = errorRing.count
    }

    // MARK: - Error ring buffer

    /// Records a new error-severity event. Call when an error toast is observed.
    public func recordError() {
        let now = Date()
        errorRing.append(ErrorEntry(date: now))
        pruneErrorRing(now: now)
        errorCount = errorRing.count
    }

    /// Evicts entries older than 5 minutes and recomputes `errorCount`.
    public func pruneErrors() {
        pruneErrorRing(now: Date())
        errorCount = errorRing.count
    }

    // MARK: - Private fetch helpers

    /// Loads active kubeconfig context then probes connection and server version.
    private func fetchClusterInfo() async {
        let path = KubeconfigPath("~/.kube/config")
        guard
            let config = try? await kubeconfigLoader.load(from: path),
            let context = kubeconfigLoader.activeContext(in: config)
        else {
            clusterName = "—"
            serverVersion = "—"
            connectionBadge = .unknown
            return
        }

        clusterName = context.name
        let clusterId = ClusterId(context.cluster)
        activeClusterId = clusterId

        await probeConnection(clusterId: clusterId)
        await fetchServerVersion(clusterId: clusterId)
    }

    private func probeConnection(clusterId: ClusterId) async {
        do {
            let status = try await kubernetesApi.probeHealth(clusterId: clusterId)
            connectionBadge = ConnectionBadge(from: status.state)
        } catch {
            connectionBadge = .disconnected
        }
    }

    private func fetchServerVersion(clusterId: ClusterId) async {
        do {
            serverVersion = try await kubernetesApi.serverVersion(clusterId: clusterId)
        } catch {
            serverVersion = "—"
        }
    }

    /// Fetches CPU and memory aggregate percentages from Prometheus.
    ///
    /// Sets both to `nil` when the endpoint is not discovered or queries fail.
    private func fetchClusterCapacity() async {
        guard
            let clusterId = activeClusterId,
            let contextUUID = UUID(uuidString: clusterId.rawValue),
            let endpoint = try? await endpointDiscovery.discover(kubernetesContextId: contextUUID).first
        else {
            cpuPercent = nil
            memPercent = nil
            return
        }

        await fetchCPU(endpoint: endpoint)
        await fetchMemory(endpoint: endpoint)
    }

    private func fetchCPU(endpoint: PrometheusEndpoint) async {
        let expr = #"sum(rate(container_cpu_usage_seconds_total{container!="",pod!=""}[1m])) / sum(kube_node_status_capacity{resource="cpu"})"#
        let query = PromQuery.instant(expr: expr)
        do {
            let result = try await prometheusQuery.instantQuery(query, endpoint: endpoint)
            if case .instantVector(let samples) = result, let first = samples.first {
                cpuPercent = min(100.0, first.value * 100.0)
            } else {
                cpuPercent = nil
            }
        } catch {
            cpuPercent = nil
        }
    }

    private func fetchMemory(endpoint: PrometheusEndpoint) async {
        let expr = #"sum(container_memory_working_set_bytes{container!="",pod!=""}) / sum(kube_node_status_capacity_memory_bytes)"#
        let query = PromQuery.instant(expr: expr)
        do {
            let result = try await prometheusQuery.instantQuery(query, endpoint: endpoint)
            if case .instantVector(let samples) = result, let first = samples.first {
                memPercent = min(100.0, first.value * 100.0)
            } else {
                memPercent = nil
            }
        } catch {
            memPercent = nil
        }
    }

    // MARK: - Private helpers

    private func pruneErrorRing(now: Date) {
        errorRing = errorRing.filter {
            now.timeIntervalSince($0.date) < Self.errorWindowSeconds
        }
    }
}
