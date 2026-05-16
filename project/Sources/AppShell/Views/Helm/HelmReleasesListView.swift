// Views/Helm/HelmReleasesListView.swift — app_shell bounded context
// DDD role: View — Helm releases list (Onda 2)
// ADR ref: ADR-0015 (Helm native phased), ADR-0046 (rollback lease mutex)

import SwiftUI
import SharedKernel
import HelmManagement

// MARK: - HelmReleasesListView

/// Table view listing all deployed Helm releases for the active cluster.
///
/// Columns: Name / Namespace / Chart / App Version / Revision / Status / Updated / Age.
/// Row tap opens a `.helmRelease` tab. Context menu exposes History, Rollback,
/// Get Values, Get Manifest, and Delete.
public struct HelmReleasesListView: View {

    public let clusterId: ClusterId

    @State private var viewModel = HelmReleasesViewModel()
    @State private var rollbackTarget: HelmReleaseRow?
    @State private var showRollbackSheet: Bool = false

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            tableContent
        }
        .task { await viewModel.start(clusterId: clusterId) }
        .sheet(isPresented: $showRollbackSheet) {
            rollbackSheetContent
        }
    }

    // MARK: Private views

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            TextField("Filter releases…", text: $viewModel.searchText)
                .textFieldStyle(.plain)
            Spacer()
            NamespaceFilterPicker(selection: Binding(
                get: { viewModel.namespace },
                set: { ns in
                    viewModel.namespace = ns
                    Task { await viewModel.start(clusterId: clusterId) }
                }
            ))
            Button {
                Task { await viewModel.start(clusterId: clusterId) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help("Refresh releases")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private var tableContent: some View {
        switch viewModel.releases {
        case .idle, .loading where (viewModel.releases.value ?? []).isEmpty:
            loadingView
        case .failure(let error):
            errorView(error)
        default:
            releaseTable
        }
    }

    private var releaseTable: some View {
        Table(viewModel.filteredRows, selection: $viewModel.selectedReleaseId) {
            TableColumn("Name") { row in
                Text(row.name).fontWeight(.medium)
            }
            TableColumn("Namespace", value: \.namespace)
            TableColumn("Chart", value: \.chart)
            TableColumn("App Version", value: \.appVersion)
            TableColumn("Revision") { row in
                Text("\(row.revision)").monospacedDigit()
            }
            TableColumn("Status") { row in
                HelmStatusBadge(status: row.status)
            }
            TableColumn("Updated") { row in
                Text(relativeDate(row.updatedRFC3339))
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenuItems(ids: ids)
        } primaryAction: { ids in
            openDetailForFirst(ids: ids)
        }
    }

    @ViewBuilder
    private func contextMenuItems(ids: Set<UUID>) -> some View {
        Button("View History") { openDetailForFirst(ids: ids) }
        Divider()
        Button("Rollback…") { beginRollback(ids: ids) }
        Divider()
        Button("Get Values") {}
        Button("Get Manifest") {}
        Divider()
        Button("Delete", role: .destructive) {
            Task { await uninstallFirst(ids: ids) }
        }
    }

    @ViewBuilder
    private var rollbackSheetContent: some View {
        if let target = rollbackTarget {
            HelmRollbackSheet(
                release: ReleaseRef(name: target.name, namespace: target.namespace),
                currentRevision: target.revision,
                historyEntries: historyForTarget(target),
                clusterId: clusterId
            ) {
                showRollbackSheet = false
                Task { await viewModel.start(clusterId: clusterId) }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading releases…")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle).foregroundStyle(.orange)
            Text(error.localizedDescription).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.start(clusterId: clusterId) } }
                .buttonStyle(.borderedProminent)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func openDetailForFirst(ids: Set<UUID>) {
        guard let id = ids.first,
              let row = viewModel.filteredRows.first(where: { $0.id == id }) else { return }
        Task { await viewModel.openDetail(row: row, clusterId: clusterId) }
    }

    private func beginRollback(ids: Set<UUID>) {
        guard let id = ids.first,
              let row = viewModel.filteredRows.first(where: { $0.id == id }) else { return }
        rollbackTarget = row
        showRollbackSheet = true
    }

    private func uninstallFirst(ids: Set<UUID>) async {
        guard let id = ids.first,
              let row = viewModel.filteredRows.first(where: { $0.id == id }) else { return }
        await viewModel.uninstall(
            release: ReleaseRef(name: row.name, namespace: row.namespace),
            clusterId: clusterId
        )
    }

    private func historyForTarget(_ row: HelmReleaseRow) -> [ReleaseHistoryEntry] {
        // History is loaded lazily in HelmReleaseDetailView; provide empty stub here.
        []
    }

    private func relativeDate(_ rfc3339: String) -> String {
        let fmt = ISO8601DateFormatter()
        guard let date = fmt.date(from: rfc3339) else { return rfc3339 }
        let delta = Date().timeIntervalSince(date)
        switch delta {
        case ..<60:         return "just now"
        case ..<3600:       return "\(Int(delta / 60))m ago"
        case ..<86400:      return "\(Int(delta / 3600))h ago"
        default:            return "\(Int(delta / 86400))d ago"
        }
    }
}
