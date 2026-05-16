// Views/Resources/Cluster/NodesListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Cluster category — cluster-scoped)
// ADR ref: ADR-0050 (resource navigation taxonomy)
//          Row tap -> nodeDebug tab. Context menu: cordon / drain actions.

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - NodeRow

/// Table row projection for a Kubernetes Node.
public struct NodeRow: Identifiable, Hashable, Sendable {
    /// Kubernetes object UID.
    public let id: String
    public let name: String
    public let status: String
    public let role: String
    public let version: String
    public let internalIP: String
    public let osImage: String
    public let kernelVersion: String
    public let ageSeconds: Int
    /// Live metric series for CPU / Memory / Disk mini-bars (ADR-0059).
    /// Empty when no metric feed is available.
    public var metricSeries: [MetricSeries]

    public init(
        id: String, name: String, status: String, role: String, version: String,
        internalIP: String, osImage: String, kernelVersion: String, ageSeconds: Int,
        metricSeries: [MetricSeries] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.role = role
        self.version = version
        self.internalIP = internalIP
        self.osImage = osImage
        self.kernelVersion = kernelVersion
        self.ageSeconds = ageSeconds
        self.metricSeries = metricSeries
    }
}

// MARK: - NodesListViewModel

/// View model for the Kubernetes Nodes list view.
///
/// Cluster-scoped. Projects `ResourceListItem` values to typed `NodeRow` rows,
/// capturing commonly displayed columns from `labels` / `annotations`.
@Observable
@MainActor
public final class NodesListViewModel {

    // MARK: State

    /// Lifecycle state of the nodes list.
    public var loadState: AsyncResource<[NodeRow]> = .idle

    /// Free-text search filter applied client-side.
    public var searchText: String = ""

    /// Node selected for the `nodeDebug` tab.
    public var selectedNodeName: String?

    // MARK: Computed

    /// Rows after applying the search filter.
    public var filteredRows: [NodeRow] {
        guard let rows = loadState.value, !searchText.isEmpty else {
            return loadState.value ?? []
        }
        return rows.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.role.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var listPort

    private let logger = Logger(label: "k8smgr.app_shell.nodes_list")

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads nodes for the given cluster.
    public func start(clusterId: ClusterId) async {
        await reload(clusterId: clusterId)
    }

    /// Re-fetches nodes.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("nodes reload cluster=\(clusterId.rawValue)")
        let gvk = GroupVersionKind.core("Node")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: nil, clusterId: clusterId)
            let rows = items.map(Self.project)
            logger.info("nodes loaded count=\(rows.count)")
            loadState = .success(rows)
        } catch {
            logger.error("nodes load failed — \(error)")
            loadState = .failure(error)
        }
    }

    // MARK: Actions

    /// Stub — cordon action (Onda 3: dispatches PATCH via mutation port).
    public func cordon(nodeName: String) {
        logger.info("cordon requested node=\(nodeName) (stub — Onda 3)")
    }

    /// Stub — drain action (Onda 3: dispatches drain command via mutation port).
    public func drain(nodeName: String) {
        logger.info("drain requested node=\(nodeName) (stub — Onda 3)")
    }

    // MARK: Private projection

    private static func project(_ item: ResourceListItem) -> NodeRow {
        let role = item.labels
            .keys
            .filter { $0.hasPrefix("node-role.kubernetes.io/") }
            .map { $0.replacingOccurrences(of: "node-role.kubernetes.io/", with: "") }
            .sorted()
            .joined(separator: ",")
        return NodeRow(
            id: item.uid,
            name: item.name,
            status: item.status,
            role: role.isEmpty ? "worker" : role,
            version: item.annotations["status.nodeInfo.kubeletVersion"] ?? "—",
            internalIP: item.annotations["status.addresses.InternalIP"] ?? "—",
            osImage: item.annotations["status.nodeInfo.osImage"] ?? "—",
            kernelVersion: item.annotations["status.nodeInfo.kernelVersion"] ?? "—",
            ageSeconds: item.ageSeconds
        )
    }
}

// MARK: - NodesListView

/// Displays cluster-scoped Kubernetes Nodes with cordon/drain context menu actions.
///
/// Row tap triggers a `nodeDebug` tab navigation (handled by `ActiveTabContentView`).
@MainActor
public struct NodesListView: View {

    let clusterId: ClusterId
    /// Callback from `ActiveTabContentView` to open a nodeDebug tab.
    let onNodeDebugTap: (String) -> Void

    @State private var viewModel = NodesListViewModel()

    public init(clusterId: ClusterId, onNodeDebugTap: @escaping (String) -> Void = { _ in }) {
        self.clusterId = clusterId
        self.onNodeDebugTap = onNodeDebugTap
    }

    public var body: some View {
        ResourceListContainer(
            title: "Nodes",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            searchText: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            nodesTable
        }
        .modifier(ExportMenuContainer(
            kind: "Node",
            rows: viewModel.filteredRows.map { row in
                ResourceListRow(values: [
                    row.name, row.version, ageLabel(row.ageSeconds),
                    row.role, row.status, row.internalIP,
                ])
            },
            isHidden: viewModel.filteredRows.isEmpty
        ))
        .task { await viewModel.start(clusterId: clusterId) }
    }

    // MARK: Private views

    @ViewBuilder
    private var nodesTable: some View {
        if viewModel.filteredRows.isEmpty && !viewModel.loadState.isLoading {
            ContentUnavailableView("No Nodes", systemImage: "server.rack")
        } else {
            Table(viewModel.filteredRows) {
                TableColumn("Name") { row in
                    HStack {
                        Button(row.name) { onNodeDebugTap(row.name) }
                            .buttonStyle(.borderless)
                            .font(.body.monospaced())
                        Spacer()
                        if !row.metricSeries.isEmpty {
                            MetricMiniBarStack(series: row.metricSeries)
                        }
                    }
                }
                TableColumn("Status") { row in
                    NodeConditionBadge(rawStatus: row.status)
                }
                TableColumn("Role") { row in
                    Text(row.role).foregroundStyle(.secondary).font(.callout)
                }
                TableColumn("Version") { row in
                    Text(row.version).foregroundStyle(.secondary).font(.caption.monospaced())
                }
                TableColumn("Internal IP") { row in
                    Text(row.internalIP).foregroundStyle(.secondary).font(.caption.monospaced())
                }
                TableColumn("OS") { row in
                    Text(row.osImage).foregroundStyle(.secondary).font(.caption)
                }
                TableColumn("Age") { row in
                    Text(ageLabel(row.ageSeconds)).foregroundStyle(.secondary).font(.caption)
                }
            }
            .contextMenu(forSelectionType: NodeRow.ID.self) { ids in
                nodeContextMenu(ids: ids)
            }
        }
    }

    @ViewBuilder
    private func nodeContextMenu(ids: Set<NodeRow.ID>) -> some View {
        if let id = ids.first, let row = viewModel.filteredRows.first(where: { $0.id == id }) {
            let actions = RowActionMenuBuilder.actions(for: RowActionContext(
                kind: "Node", name: row.name, family: .cluster, canDelete: false
            ))
            ForEach(actions) { action in
                if action.id == "delete" {
                    EmptyView()
                } else {
                    Button(action.label) {}
                }
            }
            Divider()
            Button("Cordon Node") { viewModel.cordon(nodeName: row.name) }
            Button("Drain Node") { viewModel.drain(nodeName: row.name) }
            Button("Debug Node") { onNodeDebugTap(row.name) }
        }
    }
}

