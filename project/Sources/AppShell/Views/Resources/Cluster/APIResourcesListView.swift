// Views/Resources/Cluster/APIResourcesListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Cluster category — cluster-scoped)
// ADR ref: ADR-0050 (resource navigation taxonomy)
//          Loads from KindCatalogue (static + future discovery endpoint).

import SwiftUI
import Observation
import ResourceBrowser
import SharedKernel

// MARK: - APIResourceRow

/// Projection of a single API resource entry for display.
public struct APIResourceRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let group: String
    public let version: String
    public let kind: String
    public let plural: String
    public let namespaced: Bool
    public let verbs: [String]

    public init(
        group: String, version: String, kind: String,
        plural: String, namespaced: Bool, verbs: [String]
    ) {
        self.id = "\(group)/\(version)/\(kind)"
        self.group = group
        self.version = version
        self.kind = kind
        self.plural = plural
        self.namespaced = namespaced
        self.verbs = verbs
    }
}

// MARK: - APIResourcesListViewModel

/// View model for the API Resources browser view.
///
/// Populates from the `KindCatalogue` static entries (ADR-0013).
/// Future: integrate a `discoveryClient.serverResourcesForGroupVersion` port
/// to merge live CRD entries at runtime.
@Observable
@MainActor
public final class APIResourcesListViewModel {

    // MARK: State

    /// All API resource rows derived from the catalogue.
    public var allRows: [APIResourceRow] = []

    /// Free-text search applied client-side.
    public var searchText: String = ""

    /// Filter: show only namespaced (`true`) or cluster-scoped (`false`). `nil` = all.
    public var namespacedFilter: Bool?

    // MARK: Computed

    /// Rows after applying search and namespaced filter.
    public var filteredRows: [APIResourceRow] {
        var rows = allRows
        if let ns = namespacedFilter {
            rows = rows.filter { $0.namespaced == ns }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            rows = rows.filter {
                $0.kind.lowercased().contains(q) ||
                $0.group.lowercased().contains(q) ||
                $0.plural.lowercased().contains(q)
            }
        }
        return rows
    }

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads API resources from the static KindCatalogue.
    ///
    /// - Parameter clusterId: Reserved for future live-discovery integration.
    public func load(clusterId: ClusterId) {
        let catalogue = KindCatalogue()
        allRows = catalogue.all.map { descriptor in
            APIResourceRow(
                group: descriptor.gvk.group.isEmpty ? "core" : descriptor.gvk.group,
                version: descriptor.gvk.version,
                kind: descriptor.gvk.kind,
                plural: descriptor.plural,
                namespaced: descriptor.namespaced,
                verbs: descriptor.supportedVerbs.map(\.rawValue)
            )
        }
    }
}

// MARK: - APIResourcesListView

/// Displays API resource discovery results: Group / Version / Kind / Plural / Namespaced / Verbs.
@MainActor
public struct APIResourcesListView: View {

    let clusterId: ClusterId

    @State private var viewModel = APIResourcesListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            apiTable
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.load(clusterId: clusterId) }
    }

    // MARK: Private views

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("API Resources").font(.headline)
            Text("\(viewModel.filteredRows.count)").font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Spacer()
            namespacedPicker
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary).imageScale(.small)
                TextField("Search kind, group", text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.searchText = $0 }
                ))
                .textFieldStyle(.plain).font(.callout)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
            .frame(minWidth: 180, maxWidth: 260)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var namespacedPicker: some View {
        Picker("Scope", selection: Binding(
            get: { viewModel.namespacedFilter },
            set: { viewModel.namespacedFilter = $0 }
        )) {
            Text("All").tag(Bool?.none)
            Text("Namespaced").tag(Bool?.some(true))
            Text("Cluster-scoped").tag(Bool?.some(false))
        }
        .pickerStyle(.menu)
        .frame(minWidth: 130)
    }

    @ViewBuilder
    private var apiTable: some View {
        if viewModel.filteredRows.isEmpty {
            ContentUnavailableView("No API Resources", systemImage: "network")
        } else {
            Table(viewModel.filteredRows) {
                TableColumn("Group") { row in
                    Text(row.group).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                TableColumn("Version") { row in
                    Text(row.version).font(.caption.monospaced())
                }
                TableColumn("Kind") { row in
                    Text(row.kind).font(.body)
                }
                TableColumn("Plural") { row in
                    Text(row.plural).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                TableColumn("Namespaced") { row in
                    Image(systemName: row.namespaced ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(row.namespaced ? .green : .secondary)
                }
                .width(90)
                TableColumn("Verbs") { row in
                    Text(row.verbs.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
