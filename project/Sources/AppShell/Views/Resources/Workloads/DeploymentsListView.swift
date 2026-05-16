// Views/Resources/Workloads/DeploymentsListView.swift — app_shell bounded context
// DDD role: View — Deployments resource list (Onda 2)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import SharedKernel

// MARK: - DeploymentsListView

/// Kubernetes Deployment list view with per-row:
/// Name / Namespace / Pods / Replicas / Available / Age columns.
public struct DeploymentsListView: View {

    public let clusterId: ClusterId
    public let namespace: String?

    @State private var viewModel = DeploymentsListViewModel()
    @Environment(\.onResourceSelect) private var onResourceSelect

    /// `apps/v1/Deployment` is the GVK for every row in this view; cached as a
    /// constant so the `.onChange` handler can build a `ResourceRef` without
    /// reaching into the view model.
    private static let deploymentKind = ResourceKind(group: "apps", version: "v1", kind: "Deployment")

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
        .overlay(alignment: .bottomTrailing) {
            ResourceListFAB(
                kind: "Deployment",
                clusterId: clusterId,
                hasSelection: viewModel.selectedId != nil,
                onPath: { _ in /* Onda 3: route to kind-skeleton editor */ }
            )
        }
        .task(id: clusterId) {
            await viewModel.start(clusterId: clusterId, namespace: namespace)
        }
        .onChange(of: viewModel.selectedId) { _, newValue in
            propagateSelection(uid: newValue)
        }
    }

    /// Lifts the table selection into the surrounding tab content view via
    /// the `\.onResourceSelect` environment closure so `ResourceDetailDrawer`
    /// (owned by `ActiveTabContentView`) can present without each list view
    /// re-implementing inspector lifecycle.
    private func propagateSelection(uid: String?) {
        guard let uid,
              let row = viewModel.filteredRows.first(where: { $0.id == uid }) else {
            onResourceSelect(nil)
            return
        }
        let ref = ResourceRef(
            kind: Self.deploymentKind,
            namespace: row.namespace.isEmpty ? nil : row.namespace,
            name: row.name
        )
        onResourceSelect(ref)
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
