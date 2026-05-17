// Views/Resources/Workloads/PodsListView.swift — app_shell bounded context
// DDD role: View — Pods resource list (Onda 2)
// ADR ref: ADR-0050 (resource navigation taxonomy)
// ADR ref: ADR-0073 (inspector trailing column — row tap routes to inspector)

import SwiftUI
import SharedKernel

// MARK: - PodsListView

/// Kubernetes Pod list view with per-row: Name / Namespace / Status / Ready /
/// Restarts / CPU / Memory / Node / Age columns.
///
/// CPU and Memory columns show "—" until Prometheus integration lands.
///
/// Row selection routes to the Inspector trailing column per ADR-0073.
/// The "Open in Tab" context-menu item is the explicit escape hatch for
/// side-by-side comparison via `DocumentTab.resourceDetail`.
public struct PodsListView: View {

    public let clusterId: ClusterId
    public let namespace: String?

    @State private var viewModel = PodsListViewModel()

    /// Inspector view model injected from the environment (ADR-0073).
    /// `nil` when the Inspector is not wired (e.g. Xcode previews).
    @Environment(\.resourceInspector) private var inspector

    public init(clusterId: ClusterId, namespace: String?) {
        self.clusterId = clusterId
        self.namespace = namespace
    }

    public var body: some View {
        ResourceListContainer(
            title: "Pods",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            namespace: Binding(
                get: { viewModel.namespace },
                set: { viewModel.namespace = $0 }
            ),
            searchText: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            podTable
        }
        // Explicit full-panel frame before the overlay guarantees the FAB
        // anchor does not follow the Table's variable intrinsic height during
        // the skeleton→data transition (ADR-0066 §"Positioning").
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            ResourceListFAB(
                kind: "Pod",
                clusterId: clusterId,
                hasSelection: viewModel.selectedId != nil,
                onPath: { handleFABPath($0) }
            )
        }
        .modifier(ExportMenuContainer(
            kind: "Pod",
            rows: viewModel.filteredRows.map { row in
                ResourceListRow(values: [
                    row.name, row.namespace, row.phase.rawValue,
                    "\(row.readyContainers)/\(row.totalContainers)",
                    "\(row.restartCount)", row.nodeName, row.age,
                ])
            },
            isHidden: viewModel.filteredRows.isEmpty
        ))
        .task(id: clusterId) {
            await viewModel.start(clusterId: clusterId, namespace: namespace)
        }
        // ADR-0073 §"Row tap routing": selection → Inspector (no new tab opened).
        .onChange(of: viewModel.selectedId) { _, newValue in
            routeSelectionToInspector(uid: newValue)
        }
    }

    /// Routes a pod row selection to the Inspector trailing column (ADR-0073).
    ///
    /// Builds an `InspectorKey` from the selected row's identity and calls
    /// `inspector.setSelection(_:)`, which surfaces the Inspector if hidden.
    /// Passing `nil` clears the Inspector selection but does not hide the column.
    private func routeSelectionToInspector(uid: String?) {
        guard let uid,
              let row = viewModel.filteredRows.first(where: { $0.id == uid }) else {
            // Row deselected — clear inspector key without closing the panel.
            inspector?.selectedKey = nil
            return
        }
        let key = InspectorKey(
            clusterId: clusterId,
            kind: "Pod",
            name: row.name,
            namespace: row.namespace.isEmpty ? nil : row.namespace
        )
        inspector?.setSelection(key)
    }

    private func handleFABPath(_ path: FABCreatePath) {
        switch path {
        case .createFromScratch, .pasteFromClipboard, .forkFromSelected:
            // ADR-0066: open Apply YAML tab; content pre-fill is a forward reference
            // (requires DocumentTab.applyYAML initialContent extension — ADR-0064).
            Task { await viewModel.openApplyYAML(clusterId: clusterId) }
        }
    }

    // MARK: Private

    private var emptyStateMessage: String {
        if !viewModel.searchText.isEmpty {
            return "No pods match \"\(viewModel.searchText)\"."
        }
        if let ns = viewModel.namespace {
            return "Namespace \"\(ns)\" has no pods."
        }
        return "This cluster has no pods."
    }

    private var emptyStateSystemImage: String { "shippingbox" }

    @ViewBuilder
    private var podTable: some View {
        switch viewModel.loadState {
        case .idle where viewModel.rows.isEmpty,
             .loading where viewModel.rows.isEmpty:
            WorkloadListSkeleton()
        case .failure(let error):
            ErrorStateView(
                title: "Failed to load Pods",
                error: error,
                retryable: true,
                onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
            )
        case .success where viewModel.filteredRows.isEmpty:
            EmptyStateView(
                title: "No Pods",
                message: emptyStateMessage,
                systemImage: emptyStateSystemImage
            )
        default:
            podTableContent
        }
    }

    private var podTableContent: some View {
        Table(viewModel.filteredRows, selection: $viewModel.selectedId) {
            TableColumn("Name") { row in
                HStack {
                    Text(row.name)
                    Spacer()
                    if !row.metricSeries.isEmpty {
                        MetricMiniBarStack(series: row.metricSeries)
                    }
                }
                .onAppear { viewModel.rowDidAppear(id: row.id) }
                .onDisappear { viewModel.rowDidDisappear(id: row.id) }
            }
            TableColumn("Namespace", value: \.namespace)
            TableColumn("Status") { row in
                let chip = StatusChipSemantic.podPhaseChip(phase: row.phase.rawValue)
                StatusChip(variant: chip.variant, label: chip.label, tooltip: chip.tooltip)
            }
            TableColumn("Ready") { row in
                Text("\(row.readyContainers)/\(row.totalContainers)")
                    .monospacedDigit()
            }
            TableColumn("Restarts") { row in
                Text("\(row.restartCount)")
                    .monospacedDigit()
            }
            TableColumn("CPU") { row in
                Text(row.cpuUsage ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(row.cpuUsage == nil ? .secondary : .primary)
            }
            TableColumn("Memory") { row in
                Text(row.memUsage ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(row.memUsage == nil ? .secondary : .primary)
            }
            TableColumn("Node", value: \.nodeName)
            TableColumn("Age", value: \.age)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            podContextMenuItems(ids: ids)
        }
    }

    @ViewBuilder
    private func podContextMenuItems(ids: Set<String>) -> some View {
        // ADR-0073 §"Row tap routing": "Open in Tab" is the explicit escape hatch
        // for side-by-side comparison. Routes through OpenTabsActor, preserving
        // the ADR-0070 bidirectional sync invariant.
        if let uid = ids.first,
           let row = viewModel.filteredRows.first(where: { $0.id == uid }) {
            Button {
                Task { await viewModel.openDetailTab(clusterId: clusterId, row: row) }
            } label: {
                Label("Open in Tab", systemImage: "plus.rectangle.on.rectangle")
            }
            Divider()
        }

        let actions = RowActionMenuBuilder.actions(for: RowActionContext(
            kind: "Pod", name: ids.first ?? "", family: .workloads
        ))
        ForEach(actions) { action in
            if action.id == "delete" {
                Divider()
                Button("Delete\u{2026}", role: .destructive) { viewModel.confirmDelete(ids: ids) }
            } else if action.id == "port-forward" {
                Button("Port Forward") { viewModel.portForwardRequested(ids: ids) }
            } else {
                Button(action.label) {}
            }
        }
    }

}
