// Views/Resources/RBAC/CertificateSigningRequestsListView.swift — app_shell bounded context
// DDD role: View (Onda 2, RBAC category — cluster-scoped)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - CertificateSigningRequestsListViewModel

/// View model for the Kubernetes CertificateSigningRequests list view.
///
/// Cluster-scoped. Loads `certificates.k8s.io/v1 CertificateSigningRequest`.
@Observable
@MainActor
public final class CertificateSigningRequestsListViewModel {

    // MARK: State

    /// Lifecycle state of the CSR list.
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

    private let logger = Logger(label: "k8smgr.app_shell.csrs_list")

    private static let gvk = GroupVersionKind(
        group: "certificates.k8s.io", version: "v1", kind: "CertificateSigningRequest"
    )

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads CSRs for the given cluster.
    public func start(clusterId: ClusterId) async {
        await reload(clusterId: clusterId)
    }

    /// Re-fetches CSRs.
    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        logger.info("csrs reload cluster=\(clusterId.rawValue)")
        do {
            let items = try await listPort.list(gvk: Self.gvk, namespace: nil, clusterId: clusterId)
            logger.info("csrs loaded count=\(items.count)")
            loadState = .success(items)
        } catch {
            logger.error("csrs load failed — \(error)")
            loadState = .failure(error)
        }
    }
}

// MARK: - CertificateSigningRequestsListView

/// Displays cluster-scoped Kubernetes CSRs: Name / Signer / Requester / Condition / Age.
@MainActor
public struct CertificateSigningRequestsListView: View {

    let clusterId: ClusterId

    @State private var viewModel = CertificateSigningRequestsListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "Certificate Signing Requests",
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
            ProgressView("Loading Certificate Signing Requests…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let error):
            errorView(error)
        default:
            List(viewModel.filteredRows, id: \.uid) { item in
                CSRRow(item: item)
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

// MARK: - CSRRow

private struct CSRRow: View {
    let item: ResourceListItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.monospaced())
                let requester = item.annotations["spec.username"] ?? "—"
                Text(requester).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusChip(
                variant: StatusChipSemantic.chipVariant(forRawStatus: item.status),
                label: item.status
            )
            Text(ageLabel(item.ageSeconds)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
