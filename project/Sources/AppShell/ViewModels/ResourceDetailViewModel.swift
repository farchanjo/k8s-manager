// ViewModels/ResourceDetailViewModel.swift — app_shell bounded context
// DDD role: ViewModel — resource detail drawer
// ADR ref: ADR-0050 (tab system), ADR-0021 (detail drawer, Onda 2)

import Foundation
import Observation
import Dependencies
import Logging
import MetricsObservability
import ResourceBrowser
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.resource_detail")

// MARK: - Value types

/// A single key-value property row shown in the Properties section.
public struct PropertyRow: Identifiable, Sendable {
    /// Stable identifier for diffing.
    public let id: String
    /// Display label (left column).
    public let label: String
    /// Formatted display value (right column).
    public let value: String
    /// When non-nil, tapping the value opens a tab for this ref.
    public let linkedRef: ResourceRef?

    public init(
        label: String,
        value: String,
        linkedRef: ResourceRef? = nil
    ) {
        self.id = label
        self.label = label
        self.value = value
        self.linkedRef = linkedRef
    }
}

/// A container row in the Containers section.
public struct ContainerRow: Identifiable, Sendable {
    /// Container name.
    public let id: String
    /// OCI image reference (e.g. `nginx:1.25`).
    public let image: String
    /// Current lifecycle state string from the Kubernetes API.
    public let state: String
    /// Whether the container passed its readiness probe.
    public let ready: Bool

    public init(id: String, image: String, state: String, ready: Bool) {
        self.id = id
        self.image = image
        self.state = state
        self.ready = ready
    }
}

/// A volume entry in the Volumes section.
public struct VolumeRow: Identifiable, Sendable {
    /// Volume name as declared in the pod spec.
    public let id: String
    /// Human-readable volume type label (e.g. `"PVC"`, `"ConfigMap"`).
    public let volumeType: String
    /// Source identifier (claim name, ConfigMap name, etc.).
    public let source: String

    public init(id: String, volumeType: String, source: String) {
        self.id = id
        self.volumeType = volumeType
        self.source = source
    }
}

/// A recent event row in the Events section.
public struct EventRow: Identifiable, Sendable {
    /// Stable row id derived from `reason + lastSeen`.
    public let id: String
    /// Kubernetes event type: `Normal` or `Warning`.
    public let eventType: EventSummary.EventType
    /// Short reason code.
    public let reason: String
    /// Human-readable age string for `lastTimestamp`.
    public let lastSeen: String
    /// Truncated message preview (first 120 chars).
    public let message: String

    public init(
        eventType: EventSummary.EventType,
        reason: String,
        lastSeen: String,
        message: String
    ) {
        self.id = "\(reason)-\(lastSeen)"
        self.eventType = eventType
        self.reason = reason
        self.lastSeen = lastSeen
        self.message = message
    }
}

/// Metric kind selector for the chart tab chip.
public enum MetricKind: String, CaseIterable, Sendable {
    case cpu = "CPU"
    case memory = "Memory"
    case network = "Network"
    case io = "IO"
}

/// Time-window selector for the chart range picker.
public enum TimeWindow: String, CaseIterable, Sendable {
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case oneHour = "1h"
    case sixHours = "6h"
    case twentyFourHours = "24h"

    /// Duration in seconds for this window.
    var seconds: Int {
        switch self {
        case .fiveMinutes:       return 5 * 60
        case .fifteenMinutes:    return 15 * 60
        case .oneHour:           return 60 * 60
        case .sixHours:          return 6 * 60 * 60
        case .twentyFourHours:   return 24 * 60 * 60
        }
    }

    /// Preferred step resolution for this window.
    var stepSeconds: Int {
        max(seconds / 200, 1)
    }
}

/// A single (timestamp, value) point for Swift Charts rendering.
public struct MetricPoint: Identifiable, Sendable {
    /// Date derived from the Unix timestamp.
    public let id: Double
    /// Point timestamp.
    public let date: Date
    /// Numeric value.
    public let value: Double

    public init(tUnix: Double, value: Double) {
        self.id = tUnix
        self.date = Date(timeIntervalSince1970: tUnix)
        self.value = value
    }
}

// MARK: - ResourceDetailViewModel

/// View model for the resource detail drawer.
///
/// Owns all async state for properties, containers, volumes, events, and
/// metrics. Opened via `.inspector` or slide-in drawer on macOS 14+.
@Observable
@MainActor
public final class ResourceDetailViewModel {

    // MARK: Published state

    /// Projected property rows from the fetched `ResourceDetail`.
    public var properties: [PropertyRow] = []
    /// Container rows for Pods; empty for other kinds.
    public var containers: [ContainerRow] = []
    /// Volume rows for Pods; empty for other kinds.
    public var volumes: [VolumeRow] = []
    /// Last 5 events for the selected resource.
    public var events: [EventRow] = []
    /// Currently selected metric kind (chart tab).
    public var selectedMetric: MetricKind = .cpu
    /// Currently selected time window.
    public var selectedWindow: TimeWindow = .oneHour
    /// Time-series data points rendered in the chart.
    public var metricSeries: [MetricPoint] = []
    /// True while the initial detail fetch is in progress.
    public var isLoading = false
    /// Prometheus is unavailable; show placeholder instead of chart.
    public var prometheusUnavailable = false

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var listPort

    @ObservationIgnored
    @Dependency(\.prometheusQuery) private var prometheusPort

    // MARK: Navigation callback

    /// Called when an action needs to open a new tab. Injected by the parent view.
    public var onOpenTab: ((DocumentTab) -> Void)?

    /// Called when the drawer should be dismissed.
    public var onClose: (() -> Void)?

    // MARK: Init

    public init() {}

    // MARK: - Lifecycle

    /// Begins fetching resource detail and metrics for the given ref.
    ///
    /// - Parameters:
    ///   - clusterId: Active cluster context.
    ///   - ref: The resource to fetch.
    public func start(clusterId: ClusterId, ref: ResourceRef) async {
        isLoading = true
        defer { isLoading = false }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchDetail(clusterId: clusterId, ref: ref) }
            group.addTask { await self.fetchMetrics(clusterId: clusterId, ref: ref) }
        }
    }

    // MARK: - Metric refresh

    /// Re-fetches metric data when the window or kind selection changes.
    public func refreshMetrics(clusterId: ClusterId, ref: ResourceRef) async {
        await fetchMetrics(clusterId: clusterId, ref: ref)
    }

    // MARK: - Action intents

    /// Opens a YAML editor tab for the current resource.
    public func openEditor(clusterId: ClusterId, ref: ResourceRef) {
        onOpenTab?(.yamlEditor(clusterId: clusterId, ref: ref, draft: ""))
    }

    /// Opens an exec (shell) tab for the current resource.
    public func openShell(clusterId: ClusterId, ref: ResourceRef, container: String? = nil) {
        onOpenTab?(.exec(clusterId: clusterId, podRef: ref, container: container))
    }

    /// Opens a logs tab for the given container.
    public func openLogs(clusterId: ClusterId, ref: ResourceRef, container: String? = nil) {
        onOpenTab?(.logs(clusterId: clusterId, podRef: ref, container: container, follow: true))
    }

    /// Signals the drawer should be dismissed.
    public func close() {
        onClose?()
    }

    /// Confirm-restart stub — ADR-0012 double-confirm handled in Onda 3.
    public func confirmRestart(clusterId: ClusterId, ref: ResourceRef) async {
        log.info("restart requested ref=\(ref.name) (stub — Onda 3)")
    }

    /// Confirm-delete stub — ADR-0012 destructive confirm handled in Onda 3.
    public func confirmDelete(clusterId: ClusterId, ref: ResourceRef) async {
        log.info("delete requested ref=\(ref.name) (stub — Onda 3)")
    }

    // MARK: - Private fetchers

    private func fetchDetail(clusterId: ClusterId, ref: ResourceRef) async {
        let gvk = GroupVersionKind(
            group: ref.kind.group,
            version: ref.kind.version,
            kind: ref.kind.kind
        )
        log.info("fetchDetail kind=\(gvk.kind) name=\(ref.name)")
        do {
            let detail = try await listPort.get(
                gvk: gvk,
                name: ref.name,
                namespace: ref.namespace,
                clusterId: clusterId
            )
            properties = Self.buildProperties(from: detail)
            containers = Self.buildContainers(from: detail)
            volumes = Self.buildVolumes(from: detail)
            events = detail.recentEvents.prefix(5).map(EventRow.init)
            log.info("fetchDetail OK props=\(properties.count)")
        } catch {
            log.error("fetchDetail FAILED — \(error)")
        }
    }

    private func fetchMetrics(clusterId: ClusterId, ref: ResourceRef) async {
        prometheusUnavailable = false
        let expr = promQLExpression(for: selectedMetric, ref: ref)
        let range = buildTimeRange(window: selectedWindow)
        let query = PromQuery.range(expr: expr, range: range)
        log.info("fetchMetrics metric=\(selectedMetric.rawValue) window=\(selectedWindow.rawValue)")
        do {
            let result = try await prometheusPort.rangeQuery(query, endpoint: .stub)
            metricSeries = Self.extractPoints(from: result)
            log.info("fetchMetrics OK points=\(metricSeries.count)")
        } catch {
            log.info("fetchMetrics unavailable — \(error)")
            metricSeries = []
            prometheusUnavailable = true
        }
    }

    // MARK: - Projection helpers

    private static func buildProperties(from detail: ResourceDetail) -> [PropertyRow] {
        let item = detail.listItem
        var rows: [PropertyRow] = [
            PropertyRow(label: "Name", value: item.name),
            PropertyRow(label: "Namespace", value: item.namespace ?? "(cluster-scoped)"),
            PropertyRow(label: "Age", value: ageString(seconds: item.ageSeconds)),
            PropertyRow(label: "Status", value: item.status),
            PropertyRow(label: "UID", value: item.uid),
            PropertyRow(label: "Created", value: item.creationTimestamp),
        ]
        if !item.labels.isEmpty {
            let labelText = item.labels.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            rows.append(PropertyRow(label: "Labels", value: labelText))
        }
        if !item.annotations.isEmpty {
            rows.append(PropertyRow(label: "Annotations", value: "\(item.annotations.count) keys"))
        }
        return rows
    }

    private static func buildContainers(from detail: ResourceDetail) -> [ContainerRow] {
        guard detail.listItem.gvk.kind == "Pod" else { return [] }
        let stateRaw = detail.listItem.annotations["container.state"] ?? "running"
        let imageName = detail.listItem.annotations["container.image"] ?? "unknown"
        return [
            ContainerRow(
                id: detail.listItem.name,
                image: imageName,
                state: stateRaw,
                ready: detail.listItem.status == "Running"
            )
        ]
    }

    private static func buildVolumes(from detail: ResourceDetail) -> [VolumeRow] {
        guard detail.listItem.gvk.kind == "Pod" else { return [] }
        return []
    }

    private static func extractPoints(from result: PromQueryResult) -> [MetricPoint] {
        guard case .rangeMatrix(let series) = result,
              let first = series.first else { return [] }
        return first.points.map { MetricPoint(tUnix: $0.tUnix, value: $0.value) }
    }

    private func promQLExpression(for metric: MetricKind, ref: ResourceRef) -> String {
        let ns = ref.namespace ?? ""
        let name = ref.name
        switch metric {
        case .cpu:
            return #"sum(rate(container_cpu_usage_seconds_total{pod="\#(name)",namespace="\#(ns)"}[2m]))"#
        case .memory:
            return #"sum(container_memory_working_set_bytes{pod="\#(name)",namespace="\#(ns)"})"#
        case .network:
            return #"sum(rate(container_network_receive_bytes_total{pod="\#(name)",namespace="\#(ns)"}[2m]))"#
        case .io:
            return #"sum(rate(container_fs_reads_bytes_total{pod="\#(name)",namespace="\#(ns)"}[2m]))"#
        }
    }

    private func buildTimeRange(window: TimeWindow) -> TimeRange {
        let now = Date()
        let start = now.addingTimeInterval(-Double(window.seconds))
        let fmt = ISO8601DateFormatter()
        return TimeRange(
            start: fmt.string(from: start),
            end: fmt.string(from: now),
            stepSeconds: window.stepSeconds
        )
    }

    static func ageString(seconds: Int) -> String {
        switch seconds {
        case ..<60:    return "\(seconds)s"
        case ..<3600:  return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default:       return "\(seconds / 86400)d"
        }
    }
}

// MARK: - EventRow init from EventSummary

private extension EventRow {
    init(_ summary: EventSummary) {
        self.init(
            eventType: summary.eventType,
            reason: summary.reason,
            lastSeen: summary.lastTimestamp,
            message: String(summary.message.prefix(120))
        )
    }
}

// MARK: - PrometheusEndpoint stub

private extension PrometheusEndpoint {
    /// Placeholder endpoint used when no real endpoint is configured.
    ///
    /// The `prometheusPort` will throw `PrometheusQueryError.unimplemented`
    /// against this stub, which `fetchMetrics` treats as "unavailable".
    static let stub = PrometheusEndpoint(
        id: UUID(),
        kubernetesContextId: UUID(),
        url: "http://prometheus.stub.local",
        discoverySource: .wellKnown,
        authStrategy: .none,
        insecureSkipTLSVerify: false,
        status: .unknown
    )
}
