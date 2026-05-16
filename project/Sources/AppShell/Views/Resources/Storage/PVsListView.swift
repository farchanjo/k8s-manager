// Views/Resources/Storage/PVsListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Storage category — cluster-scoped)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - PVsListViewModel

/// View model for the Kubernetes PersistentVolumes list view.
///
/// Cluster-scoped; no namespace filter. Loads core/v1 PersistentVolume.
@Observable
@MainActor
public final class PVsListViewModel {

    // MARK: State

    /// Lifecycle state of the PVs list.
    public var loadState: AsyncResource<[ResourceListItem]> = .idle

    /// Free-text search filter applied client-side.
    public var searchText: String = ""

    // MARK: Computed

    /// Rows after applying the search filter.
    public var filteredRows: [ResourceListItem] {
        guard let items = loadState.value, !searchText.isEmpty else {
            return loadState.value ?? []
        }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var listPort

    private let logger = Logger(label: "k8smgr.app_shell.pvs_list")

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads PVs for the given cluster.
    public func start(clusterId: ClusterId) async {
        await reload(clusterId: clusterId)
    }

    /// Re-fetches PVs.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("pvs reload cluster=\(clusterId.rawValue)")
        let gvk = GroupVersionKind.core("PersistentVolume")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: nil, clusterId: clusterId)
            logger.info("pvs loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("pvs load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - PVsListView

/// Displays cluster-scoped Kubernetes PersistentVolumes: Name / Status / Age.
@MainActor
public struct PVsListView: View {

    let clusterId: ClusterId

    @State private var viewModel = PVsListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Persistent Volumes",
            itemCount: viewModel.filteredRows.count,
            isLoading: viewModel.loadState.isLoading,
            searchText: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            content
        }
        .task { await viewModel.start(clusterId: clusterId) }
    }

    // MARK: Private views

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading where viewModel.filteredRows.isEmpty:
            ProgressView("Loading Persistent Volumes…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let error):
            errorView(error)
        default:
            List(viewModel.filteredRows, id: \.uid) { item in
                PVRow(item: item)
            }
            .listStyle(.inset)
        }
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(error.localizedDescription).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.reload(clusterId: clusterId) } }
                .buttonStyle(.borderedProminent)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PVRow

private struct PVRow: View {
    let item: ResourceListItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.monospaced())
                let capacity = item.annotations["storage.kubernetes.io/capacity"] ?? "—"
                Text("capacity: \(capacity)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(raw: item.status)
            Text(ageLabel(item.ageSeconds)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
