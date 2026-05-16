// Views/Resources/CustomResources/CustomResourceListView.swift — app_shell bounded context
// DDD role: View — generic CRD kind list with dynamic printer columns
// ADR ref: ADR-0052 (custom resource discovery and rendering)

import SwiftUI
import Dependencies
import ResourceBrowser
import SharedKernel

// MARK: - CustomResourceRow

/// Table row projection for a single custom resource instance.
public struct CustomResourceRow: Identifiable, Sendable, Hashable {

    /// Kubernetes object UID — stable across watch events.
    public let id: String

    /// `metadata.name`.
    public let name: String

    /// `metadata.namespace` or `""` for cluster-scoped resources.
    public let namespace: String

    /// Human-readable age string (e.g. `"5d"`, `"3h"`, `"12m"`).
    public let age: String

    /// Dynamic column values keyed by `PrinterColumn.name`.
    public let values: [String: String]

    /// Memberwise initialiser.
    public init(
        id: String,
        name: String,
        namespace: String,
        age: String,
        values: [String: String]
    ) {
        self.id = id
        self.name = name
        self.namespace = namespace
        self.age = age
        self.values = values
    }
}

// MARK: - CustomResourceListViewModel

/// View model for the generic CRD kind list view.
///
/// Loads the CRD catalog to resolve printer columns, then fetches custom
/// resource instances and maps them to `CustomResourceRow` projections.
@Observable
@MainActor
public final class CustomResourceListViewModel {

    // MARK: Published state

    /// Resolved `CRDEntry` for the current GVR. `nil` while loading.
    public var entry: CRDEntry?

    /// Loaded rows, projected from custom resource instances.
    public var rows: [CustomResourceRow] = []

    /// Currently selected row id.
    public var selectedId: String?

    /// `true` while a network call is in flight.
    public var isLoading: Bool = false

    /// Non-nil when loading fails.
    public var loadError: Error?

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.crdDiscovery) private var discoveryPort

    // MARK: Init

    /// Memberwise initialiser.
    public init() {}

    // MARK: Intents

    /// Loads the CRD catalog entry for `gvr` and fetches instances.
    public func start(clusterId: ClusterId, gvr: GroupVersionResource) async {
        isLoading = true
        loadError = nil
        do {
            let catalog = try await discoveryPort.discoverCRDs(clusterId: clusterId)
            entry = catalog.entries.first { $0.id == gvr }
            // Rows are populated by the adapter once dynamic list port is wired.
            // For now, project empty rows as placeholder.
            rows = []
            isLoading = false
        } catch {
            isLoading = false
            loadError = error
        }
    }
}

// MARK: - CustomResourceListView

/// Generic list view for any CRD kind.
///
/// Reads `printerColumns` from the resolved `CRDEntry` and builds a `Table`
/// dynamically. Falls back to Name / Namespace / Age when no columns are declared.
public struct CustomResourceListView: View {

    public let clusterId: ClusterId
    public let gvr: GroupVersionResource

    @State private var viewModel = CustomResourceListViewModel()

    /// Memberwise initialiser.
    public init(clusterId: ClusterId, gvr: GroupVersionResource) {
        self.clusterId = clusterId
        self.gvr = gvr
    }

    public var body: some View {
        ResourceListContainer(
            title: viewModel.entry?.displayName ?? gvr.resource,
            itemCount: viewModel.rows.isEmpty ? nil : viewModel.rows.count,
            isLoading: viewModel.isLoading
        ) {
            tableContent
        }
        .task { await viewModel.start(clusterId: clusterId, gvr: gvr) }
    }

    // MARK: Private views

    @ViewBuilder
    private var tableContent: some View {
        if viewModel.isLoading && viewModel.rows.isEmpty {
            loadingPlaceholder
        } else if let error = viewModel.loadError {
            errorView(error)
        } else if viewModel.rows.isEmpty {
            emptyView
        } else if viewModel.entry?.columns.isEmpty ?? true {
            fallbackTable
        } else {
            dynamicTable
        }
    }

    @ViewBuilder private var dynamicTable: some View {
        let columns = viewModel.entry?.columns ?? []
        let namespaced = viewModel.entry?.isNamespaced ?? false
        List(viewModel.rows, selection: $viewModel.selectedId) { row in
            dynamicRow(row, columns: columns, namespaced: namespaced)
        }
    }

    private func dynamicRow(
        _ row: CustomResourceRow,
        columns: [PrinterColumn],
        namespaced: Bool
    ) -> some View {
        HStack {
            Text(row.name).frame(maxWidth: .infinity, alignment: .leading)
            if namespaced {
                Text(row.namespace)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)
            }
            ForEach(columns, id: \.name) { col in
                Text(row.values[col.name] ?? "—")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(row.age)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }

    @ViewBuilder private var fallbackTable: some View {
        Table(viewModel.rows, selection: $viewModel.selectedId) {
            TableColumn("Name", value: \.name)
            TableColumn("Namespace", value: \.namespace)
            TableColumn("Age") { row in
                Text(row.age).monospacedDigit()
            }
        }
    }

    private var loadingPlaceholder: some View {
        WorkloadListSkeleton()
            .accessibilityLabel("Loading \(gvr.resource)")
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.start(clusterId: clusterId, gvr: gvr) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No \(viewModel.entry?.displayName ?? gvr.resource)",
            systemImage: "puzzlepiece.extension",
            description: Text("No instances found for this custom resource type.")
        )
    }
}
