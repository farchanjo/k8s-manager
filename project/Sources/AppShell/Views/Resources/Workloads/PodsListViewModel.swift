// Views/Resources/Workloads/PodsListViewModel.swift — app_shell bounded context
// DDD role: ViewModel — Pods resource list
// ADR ref: ADR-0050 (Onda 2 resource list views)

import Foundation
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.pods_list")

// MARK: - PodPhase

/// Kubernetes Pod phase as a closed Swift enum.
public enum PodPhase: String, Sendable, Hashable, CaseIterable {
    case pending   = "Pending"
    case running   = "Running"
    case succeeded = "Succeeded"
    case failed    = "Failed"
    case unknown   = "Unknown"

    /// Parses a raw phase string from the Kubernetes API.
    public static func from(raw: String) -> PodPhase {
        PodPhase(rawValue: raw) ?? .unknown
    }

    /// Visual accent color per phase (maps to `WorkloadStatus`).
    public var workloadStatus: WorkloadStatus {
        switch self {
        case .pending:   return .pending
        case .running:   return .running
        case .succeeded: return .succeeded
        case .failed:    return .failed
        case .unknown:   return .unknown
        }
    }
}

// MARK: - PodRow

/// Table row projection for a single Kubernetes Pod.
public struct PodRow: Identifiable, Hashable, Sendable {
    /// Kubernetes object UID — stable across watch events.
    public let id: String
    public let name: String
    public let namespace: String
    public let phase: PodPhase
    public let readyContainers: Int
    public let totalContainers: Int
    public let restartCount: Int
    /// CPU usage string (e.g. `"12m"`). `nil` when metrics unavailable.
    public let cpuUsage: String?
    /// Memory usage string (e.g. `"128Mi"`). `nil` when metrics unavailable.
    public let memUsage: String?
    public let nodeName: String
    /// Human-readable age (e.g. `"5d"`, `"3h"`, `"12m"`).
    public let age: String
    /// Live metric series for CPU / Memory mini-bars (ADR-0059).
    /// Empty when the row is off-screen or no feed is available.
    public var metricSeries: [MetricSeries]

    public init(
        id: String,
        name: String,
        namespace: String,
        phase: PodPhase,
        readyContainers: Int,
        totalContainers: Int,
        restartCount: Int,
        cpuUsage: String?,
        memUsage: String?,
        nodeName: String,
        age: String,
        metricSeries: [MetricSeries] = []
    ) {
        self.id = id
        self.name = name
        self.namespace = namespace
        self.phase = phase
        self.readyContainers = readyContainers
        self.totalContainers = totalContainers
        self.restartCount = restartCount
        self.cpuUsage = cpuUsage
        self.memUsage = memUsage
        self.nodeName = nodeName
        self.age = age
        self.metricSeries = metricSeries
    }
}

// MARK: - PodsListViewModel

/// View model for the Pods resource list view.
///
/// Fetches pods via `KubernetesResourceListPort` and projects them into
/// `PodRow` values for display in a `SwiftUI.Table`. Metrics columns
/// (CPU / Memory) show "—" until Prometheus integration lands in a later wave.
@Observable
@MainActor
public final class PodsListViewModel {

    // MARK: Published state

    public var rows: [PodRow] = []
    public var selectedId: String?
    public var namespace: String?
    public var loadState: AsyncResource<Int> = .idle
    public var searchText: String = ""

    // MARK: Computed

    public var filteredRows: [PodRow] {
        guard !searchText.isEmpty else { return rows }
        return rows.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.namespace.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var listPort

    @ObservationIgnored
    @Dependency(\.namespaceFilter) private var namespaceFilter

    @ObservationIgnored
    @Dependency(\.openTabs) private var openTabs

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Begins loading pods for the given cluster and namespace.
    /// Subscribes to the global ``NamespaceFilterActor`` so every change to
    /// the toolbar picker re-fetches pods for the new namespace.
    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = await namespaceFilter.current(for: clusterId) ?? namespace
        await reload(clusterId: clusterId)
        for await snapshot in namespaceFilter.stateStream(for: clusterId) {
            if snapshot.namespace == self.namespace { continue }
            self.namespace = snapshot.namespace
            await reload(clusterId: clusterId)
        }
    }

    /// Re-fetches pods with the current namespace filter.
    public func reload(clusterId: ClusterId) async {
        let port = listPort
        let ns = namespace
        let gvk = GroupVersionKind.core("Pod")
        log.info("pods reload cluster=\(clusterId.rawValue) namespace=\(ns ?? "<all>")")
        await AsyncLoader.run(
            setLoading: { self.loadState = .loading },
            operation: { try await port.list(gvk: gvk, namespace: ns, clusterId: clusterId) },
            onSuccess: { items in
                self.rows = items.map(Self.project)
                self.loadState = .success(self.rows.count)
                log.info("pods loaded count=\(self.rows.count)")
            },
            onFailure: { error in
                log.error("pods load failed — \(error)")
                self.loadState = .failure(error)
            }
        )
    }

    /// Opens the Apply YAML editor tab for the given cluster (ADR-0066).
    ///
    /// Called by the FAB `createFromScratch` and `pasteFromClipboard` paths.
    public func openApplyYAML(clusterId: ClusterId) async {
        await openTabs.openTab(.applyYAML(clusterId: clusterId))
    }

    /// Opens a `resourceDetail` tab for the given pod row (ADR-0073 "Open in Tab").
    ///
    /// This is the explicit escape hatch allowing operators to open a side-by-side
    /// comparison tab even though row-tap now routes to the Inspector column.
    /// Routes through `OpenTabsActor` preserving the ADR-0070 sync invariant.
    public func openDetailTab(clusterId: ClusterId, row: PodRow) async {
        let ref = ResourceRef(
            kind: ResourceKind(group: "", version: "v1", kind: "Pod"),
            namespace: row.namespace.isEmpty ? nil : row.namespace,
            name: row.name
        )
        await openTabs.openTab(.resourceDetail(clusterId: clusterId, ref: ref))
    }

    /// Confirms and executes deletion for the given row IDs (stub — Onda 3).
    public func confirmDelete(ids: Set<String>) {
        log.info("delete requested ids=\(ids.count) (stub)")
    }

    /// Records that a port-forward was requested for the selected pod rows.
    ///
    /// The caller (view) should open a `.portForward` tab after invoking this.
    public func portForwardRequested(ids: Set<String>) {
        guard let id = ids.first,
              let row = rows.first(where: { $0.id == id }) else { return }
        log.info("port-forward requested for pod=\(row.name) ns=\(row.namespace)")
    }

    /// Notifies the view model that a pod row has become visible (ADR-0059).
    ///
    /// In a concrete implementation this would register the pod with
    /// `NodeMetricsRefreshActor` so it participates in the next batch query.
    /// The stub records the event for logging.
    public func rowDidAppear(id: String) {
        log.debug("pod row appeared id=\(id) (metric activation stub)")
    }

    /// Notifies the view model that a pod row has left the viewport (ADR-0059).
    ///
    /// In a concrete implementation this would deregister the pod from the
    /// batch query coordinator so off-screen rows do not add query load.
    public func rowDidDisappear(id: String) {
        log.debug("pod row disappeared id=\(id) (metric deactivation stub)")
    }

    // MARK: Private projection

    private static func project(_ item: ResourceListItem) -> PodRow {
        PodRow(
            id: item.uid,
            name: item.name,
            namespace: item.namespace ?? "",
            phase: PodPhase.from(raw: item.status),
            readyContainers: 0,
            totalContainers: 1,
            restartCount: 0,
            cpuUsage: nil,
            memUsage: nil,
            nodeName: item.annotations["spec.nodeName"] ?? "—",
            age: ageString(seconds: item.ageSeconds)
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
