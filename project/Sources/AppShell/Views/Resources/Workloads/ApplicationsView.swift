// Views/Resources/Workloads/ApplicationsView.swift — app_shell bounded context
// DDD role: View — Applications cluster-scope list (Helm releases)
// ADR ref: ADR-0067 (applications cluster-scope view — Helm releases + GitOps extension hooks)

import SwiftUI
import HelmManagement
import SharedKernel

// MARK: - ApplicationsView

/// Cluster-scope view listing all Helm releases as application entries.
///
/// Presents a column-sortable table of Helm releases projected from the
/// ``HelmManagement`` read model. Superseded revisions are excluded. Clicking
/// a row opens the Helm release detail tab via ``ApplicationsViewModel``.
///
/// Empty state: shown when no releases exist for the active namespace filter.
/// Row action: navigates to the existing Helm release detail view (ADR-0067
/// §"Row action").
@MainActor
public struct ApplicationsView: View {

    // MARK: Properties

    public let clusterId: ClusterId

    @State private var viewModel = ApplicationsViewModel()
    @State private var sortOrder: ApplicationSortOrder = .nameAscending
    @State private var selectedRowId: ApplicationRow.ID?

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    // MARK: Body

    public var body: some View {
        Group {
            switch viewModel.viewState {
            case .idle, .loading:
                loadingView
            case .failure(let error):
                errorView(error)
            case .success(let state):
                if state.releases.isEmpty {
                    emptyState
                } else {
                    releaseTable(state.releases)
                }
            }
        }
        .navigationTitle("Applications")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.start(clusterId: clusterId) }
        .toolbar { toolbarContent }
        .accessibilityLabel("Applications list")
    }

    // MARK: Table

    @ViewBuilder
    private func releaseTable(_ rows: [ApplicationRow]) -> some View {
        Table(rows, selection: $selectedRowId) {
            TableColumn("Name") { row in
                Text(row.name)
                    .font(.callout)
                    .accessibilityLabel("Release name: \(row.name)")
            }
            .width(min: 120, ideal: 160)

            TableColumn("Chart") { row in
                Text(row.chartName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)

            TableColumn("Version") { row in
                Text(row.chartVersion)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Status") { row in
                helmStatusChip(row.status)
            }
            .width(min: 110, ideal: 140)

            TableColumn("Updated") { row in
                Text(row.updatedRelative)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)

            TableColumn("Namespace") { row in
                Text(row.namespace)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)

            TableColumn("Rev") { row in
                Text("\(row.revision)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 40, ideal: 50)
        }
        .onChange(of: selectedRowId) { _, newId in
            guard let id = newId,
                  let row = viewModel.viewState.value?.releases.first(where: { $0.id == id })
            else { return }
            Task { await viewModel.openHelmDetail(row: row, clusterId: clusterId) }
        }
    }

    // MARK: Status chip

    private func helmStatusChip(_ status: ReleaseStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(helmStatusColor(status))
                .frame(width: 7, height: 7)
            Text(helmStatusLabel(status))
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(helmStatusColor(status).opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel("Status: \(helmStatusLabel(status))")
    }

    private func helmStatusColor(_ status: ReleaseStatus) -> Color {
        switch status {
        case .deployed:                         return .green
        case .failed:                           return .red
        case .pendingInstall, .pendingUpgrade,
             .pendingRollback:                  return .orange
        case .uninstalled, .superseded:         return .secondary
        }
    }

    private func helmStatusLabel(_ status: ReleaseStatus) -> String {
        switch status {
        case .deployed:         return "Deployed"
        case .failed:           return "Failed"
        case .pendingInstall:   return "Pending Install"
        case .pendingUpgrade:   return "Pending Upgrade"
        case .pendingRollback:  return "Pending Rollback"
        case .uninstalled:      return "Uninstalled"
        case .superseded:       return "Superseded"
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "app.gift")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Helm releases in this cluster")
                .font(.headline)
            Text("Try `helm install` or import a release via the Helm tab.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Go to Helm") {
                // The "Go to Helm" action surfaces the Helm sidebar entry.
                // Handled upstream by the sidebar — this button is a convenience
                // hint only; the actual navigation is not wired at view scope per ADR-0067.
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No Helm releases. \(emptyBodyText)")
    }

    private var emptyBodyText: String {
        "Try helm install or import a release via the Helm tab."
    }

    // MARK: States

    private var loadingView: some View {
        WorkloadListSkeleton()
            .accessibilityLabel("Loading applications")
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .font(.callout)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.reload(clusterId: clusterId) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Error loading applications: \(error.localizedDescription)")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await viewModel.reload(clusterId: clusterId) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.viewState.isLoading)
            .accessibilityLabel("Refresh applications list")
        }

        ToolbarItem {
            Menu {
                Button("Name (A-Z)") {
                    Task { await viewModel.applySort(.nameAscending, clusterId: clusterId) }
                }
                Button("Name (Z-A)") {
                    Task { await viewModel.applySort(.nameDescending, clusterId: clusterId) }
                }
                Button("Chart (A-Z)") {
                    Task { await viewModel.applySort(.chartAscending, clusterId: clusterId) }
                }
                Button("Namespace (A-Z)") {
                    Task { await viewModel.applySort(.namespaceAscending, clusterId: clusterId) }
                }
                Button("Recently Updated") {
                    Task { await viewModel.applySort(.updatedDescending, clusterId: clusterId) }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort applications")
        }
    }
}
