// Views/ClusterOperations/APIResourcesView.swift — app_shell bounded context
// DDD role: View — API resource discovery browser
// ADR ref: ADR-0050 (cluster operations category, Onda 2)

import SwiftUI
import SharedKernel

// MARK: - APIResourcesView

/// Browses all Kubernetes API resources discovered from the active cluster.
///
/// Displays a searchable table (Group / Version / Kind / Plural / Short Names /
/// Namespaced / Verbs). Clicking a row opens a `customResource` tab for the GVR.
public struct APIResourcesView: View {

    /// The cluster to query.
    public let clusterId: ClusterId

    @State private var viewModel = APIResourcesViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ResourceListContainer(
            title: "API Resources",
            itemCount: viewModel.filteredResources.count,
            isLoading: viewModel.resources.isLoading,
            searchText: Binding(
                get: { viewModel.searchQuery },
                set: { viewModel.searchQuery = $0 }
            ),
            onRefresh: { await viewModel.reload(clusterId: clusterId) }
        ) {
            contentBody
        }
        .task { await viewModel.start(clusterId: clusterId) }
    }

    // MARK: Private

    @ViewBuilder
    private var contentBody: some View {
        switch viewModel.resources {
        case .idle, .loading where viewModel.filteredResources.isEmpty:
            loadingView

        case .failure(let error):
            errorView(error)

        default:
            resourceTable
        }
    }

    private var resourceTable: some View {
        Table(viewModel.filteredResources) {
            TableColumn("Kind", value: \.kind)
            TableColumn("Group", value: \.group)
            TableColumn("Version", value: \.version)
            TableColumn("Plural", value: \.plural)
            TableColumn("Short Names") { row in
                Text(row.shortNames.joined(separator: ", "))
                    .foregroundStyle(row.shortNames.isEmpty ? .secondary : .primary)
            }
            TableColumn("Namespaced") { row in
                Image(systemName: row.isNamespaced ? "checkmark" : "minus")
                    .foregroundStyle(row.isNamespaced ? .green : .secondary)
            }
            TableColumn("Verbs") { row in
                Text(row.verbs.joined(separator: " "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Discovering API resources…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.reload(clusterId: clusterId) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
