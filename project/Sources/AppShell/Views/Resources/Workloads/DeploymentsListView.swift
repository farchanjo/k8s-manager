// Views/Resources/Workloads/DeploymentsListView.swift — app_shell bounded context
// DDD role: View — Deployments resource list (Onda 2)
// ADR ref: ADR-0050 (resource navigation taxonomy)
// ADR ref: ADR-0073 (inspector trailing column — row tap routes to inspector)

import SwiftUI
import SharedKernel

// MARK: - DeploymentsListView

/// Kubernetes Deployment list view with per-row:
/// Name / Namespace / Pods / Replicas / Available / Age columns.
///
/// Row selection routes to the Inspector trailing column per ADR-0073.
/// The "Open in Tab" context-menu item is the explicit escape hatch for
/// side-by-side comparison via `DocumentTab.resourceDetail`.
public struct DeploymentsListView: View {

    public let clusterId: ClusterId
    public let namespace: String?

    @State private var viewModel = DeploymentsListViewModel()

    /// Inspector view model injected from the environment (ADR-0073).
    /// `nil` when the Inspector is not wired (e.g. Xcode previews).
    @Environment(\.resourceInspector) private var inspector

    public init(clusterId: ClusterId, namespace: String?) {
        self.clusterId = clusterId
        self.namespace = namespace
    }

    public var body: some View {
        ResourceListContainer(
            title: "Deployments",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            searchText: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            tableContent
        }
        // Explicit full-panel frame before the overlay guarantees the FAB
        // anchor does not follow the Table's variable intrinsic height during
        // the skeleton→data transition (ADR-0066 §"Positioning").
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            ResourceListFAB(
                kind: "Deployment",
                clusterId: clusterId,
                hasSelection: viewModel.selectedId != nil,
                onPath: { _ in
                    // ADR-0066: open Apply YAML tab; content pre-fill requires
                    // DocumentTab.applyYAML initialContent extension (ADR-0064).
                    Task { await viewModel.openApplyYAML(clusterId: clusterId) }
                }
            )
        }
        .task(id: clusterId) {
            await viewModel.start(clusterId: clusterId, namespace: namespace)
        }
        // ADR-0073 §"Row tap routing": selection → Inspector (no new tab opened).
        .onChange(of: viewModel.selectedId) { _, newValue in
            routeSelectionToInspector(uid: newValue)
        }
    }

    /// Routes a deployment row selection to the Inspector trailing column (ADR-0073).
    ///
    /// Builds an `InspectorKey` from the selected row and calls
    /// `inspector.setSelection(_:)`, which surfaces the Inspector if hidden.
    /// Passing `nil` clears the Inspector selection without closing the panel.
    private func routeSelectionToInspector(uid: String?) {
        guard let uid,
              let row = viewModel.filteredRows.first(where: { $0.id == uid }) else {
            inspector?.selectedKey = nil
            return
        }
        let key = InspectorKey(
            clusterId: clusterId,
            kind: "Deployment",
            name: row.name,
            namespace: row.namespace.isEmpty ? nil : row.namespace
        )
        inspector?.setSelection(key)
    }

    private var emptyStateMessage: String {
        if !viewModel.searchText.isEmpty {
            return "No deployments match \"\(viewModel.searchText)\"."
        }
        if let ns = viewModel.namespace {
            return "Namespace \"\(ns)\" has no deployments."
        }
        return "This cluster has no deployments."
    }

    private var emptyStateSystemImage: String { "square.stack.3d.up" }

    @ViewBuilder
    private var tableContent: some View {
        switch viewModel.loadState {
        case .idle where viewModel.rows.isEmpty,
             .loading where viewModel.rows.isEmpty:
            WorkloadListSkeleton()
        case .failure(let error):
            ErrorStateView(
                title: "Failed to load Deployments",
                error: error,
                retryable: true,
                onRetry: { Task { await viewModel.reload(clusterId: clusterId) } }
            )
        case .success where viewModel.filteredRows.isEmpty:
            EmptyStateView(
                title: "No Deployments",
                message: emptyStateMessage,
                systemImage: emptyStateSystemImage
            )
        default:
            deploymentsTable
        }
    }

    private var deploymentsTable: some View {
        Table(viewModel.filteredRows, selection: $viewModel.selectedId) {
            TableColumn("Name", value: \.name)
            TableColumn("Namespace", value: \.namespace)
            TableColumn("Pods") { row in
                Text(row.podsReady).monospacedDigit()
            }
            TableColumn("Replicas") { row in
                Text("\(row.replicas)").monospacedDigit()
            }
            TableColumn("Available") { row in
                Text("\(row.available)").monospacedDigit()
            }
            TableColumn("Age", value: \.age)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            deploymentContextMenuItems(ids: ids)
        }
    }

    @ViewBuilder
    private func deploymentContextMenuItems(ids: Set<String>) -> some View {
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
            kind: "Deployment", name: ids.first ?? "", family: .workloads
        ))
        ForEach(actions) { action in
            if action.id == "delete" {
                Divider()
                Button("Delete\u{2026}", role: .destructive) { viewModel.confirmDelete(ids: ids) }
            } else {
                Button(action.label) {}
            }
        }
    }

}
