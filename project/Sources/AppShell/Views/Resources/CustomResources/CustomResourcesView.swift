// Views/Resources/CustomResources/CustomResourcesView.swift — app_shell bounded context
// DDD role: View — root Custom Resources browser
// ADR ref: ADR-0052 (custom resource discovery and rendering)

import SwiftUI
import Dependencies
import ResourceBrowser
import SharedKernel

// MARK: - CustomResourcesViewModel

/// View model for the Custom Resources root view.
///
/// Subscribes to `CRDDiscoveryPort.watchCRDChanges` and exposes a grouped
/// representation suitable for the sidebar-style list.
@Observable
@MainActor
public final class CustomResourcesViewModel {

    // MARK: Published state

    /// CRD entries grouped by API group, keys sorted alphabetically.
    public var groupedEntries: [String: [CRDEntry]] = [:]

    /// Sorted API group keys for deterministic iteration.
    public var sortedGroups: [String] {
        groupedEntries.keys.sorted()
    }

    /// `true` while the initial discovery call is in flight.
    public var isLoading: Bool = false

    /// Non-nil when discovery fails.
    public var discoveryError: Error?

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.crdDiscovery) private var discoveryPort

    // MARK: Init

    /// Memberwise initialiser.
    public init() {}

    // MARK: Intents

    /// Begins watching CRD catalog changes for the given cluster.
    ///
    /// Should be called from a `.task {}` modifier on the owning view.
    /// - Parameter clusterId: The cluster to discover CRDs in.
    public func start(clusterId: ClusterId) async {
        isLoading = true
        discoveryError = nil
        do {
            let catalog = try await discoveryPort.discoverCRDs(clusterId: clusterId)
            apply(catalog: catalog)
            isLoading = false
            for try await snapshot in discoveryPort.watchCRDChanges(clusterId: clusterId) {
                apply(catalog: snapshot)
            }
        } catch {
            isLoading = false
            discoveryError = error
        }
    }

    // MARK: Private

    private func apply(catalog: CRDCatalog) {
        groupedEntries = catalog.groupedByAPIGroup()
    }
}

// MARK: - CustomResourcesView

/// Root view for the `.customResources` tab.
///
/// Renders a sidebar-style list grouped by API group. Selecting a kind opens
/// a `.customResourceKind(gvr)` tab via the `OpenTabsPort`.
public struct CustomResourcesView: View {

    public let clusterId: ClusterId

    @State private var viewModel = CustomResourcesViewModel()
    @Dependency(\.openTabs) private var openTabs

    /// Memberwise initialiser.
    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.sortedGroups.isEmpty {
                loadingView
            } else if let error = viewModel.discoveryError, viewModel.sortedGroups.isEmpty {
                errorView(error)
            } else if viewModel.sortedGroups.isEmpty {
                emptyView
            } else {
                groupList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.start(clusterId: clusterId) }
    }

    // MARK: Private views

    private var groupList: some View {
        List {
            ForEach(viewModel.sortedGroups, id: \.self) { group in
                Section(header: Text(group).font(.caption).foregroundStyle(.secondary)) {
                    ForEach(viewModel.groupedEntries[group] ?? [], id: \.id) { entry in
                        kindRow(entry: entry)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func kindRow(entry: CRDEntry) -> some View {
        HStack {
            Image(systemName: "puzzlepiece.fill")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            Text(entry.displayName)
                .font(.callout)
            Spacer()
            if entry.isNamespaced {
                Text("NS")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                let tab = DocumentTab.customResource(clusterId: clusterId, gvr: entry.id)
                await openTabs.openTab(tab)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Discovering custom resources…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .font(.callout)
        }
        .padding()
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No CRDs",
            systemImage: "puzzlepiece.extension",
            description: Text("No CustomResourceDefinitions were found in this cluster.")
        )
    }
}
