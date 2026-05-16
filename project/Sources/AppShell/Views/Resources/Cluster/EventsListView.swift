// Views/Resources/Cluster/EventsListView.swift — app_shell bounded context
// DDD role: View (Onda 2, Cluster category)
// ADR ref: ADR-0050 (resource navigation taxonomy)
//          Polls every 10s — no watch (high cardinality events stream).

import SwiftUI
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

// MARK: - ClusterEventRow

/// Table row projection for a Kubernetes Event.
public struct ClusterEventRow: Identifiable, Hashable, Sendable {
    /// Kubernetes object UID.
    public let id: String
    public let eventType: String       // "Normal" or "Warning"
    public let reason: String
    public let objectKind: String
    public let objectName: String
    public let source: String
    public let lastSeen: String
    public let count: Int
    public let message: String

    public var isWarning: Bool { eventType == "Warning" }

    public init(
        id: String, eventType: String, reason: String, objectKind: String, objectName: String,
        source: String, lastSeen: String, count: Int, message: String
    ) {
        self.id = id
        self.eventType = eventType
        self.reason = reason
        self.objectKind = objectKind
        self.objectName = objectName
        self.source = source
        self.lastSeen = lastSeen
        self.count = count
        self.message = message
    }
}

// MARK: - EventsFilterState

/// UI filter state for the Events list.
public struct EventsFilterState: Sendable, Equatable {
    /// `nil` shows all types; `"Warning"` / `"Normal"` filters to that type.
    public var typeFilter: String?
    /// Free-text applied to reason and object name.
    public var searchText: String
    /// Object kind filter (e.g. `"Pod"`, `"Deployment"`).
    public var objectKindFilter: String?

    public init(typeFilter: String? = nil, searchText: String = "", objectKindFilter: String? = nil) {
        self.typeFilter = typeFilter
        self.searchText = searchText
        self.objectKindFilter = objectKindFilter
    }
}

// MARK: - EventsListViewModel

/// View model for the Kubernetes Events list view.
///
/// Polls every 10 seconds — no watch stream (events have high cardinality).
/// Fetches core/v1 Event via `KubernetesResourceListPort`.
@Observable
@MainActor
public final class EventsListViewModel {

    // MARK: State

    /// Lifecycle state of the events list.
    public var loadState: AsyncResource<[ClusterEventRow]> = .idle

    /// Active filter state.
    public var filter: EventsFilterState = EventsFilterState()

    // MARK: Computed

    /// Rows after applying all active filters.
    public var filteredRows: [ClusterEventRow] {
        guard let rows = loadState.value else { return [] }
        return rows.filter { row in
            if let type = filter.typeFilter, row.eventType != type { return false }
            if let kind = filter.objectKindFilter, row.objectKind != kind { return false }
            if filter.searchText.isEmpty { return true }
            let q = filter.searchText.lowercased()
            return row.reason.lowercased().contains(q) || row.objectName.lowercased().contains(q)
        }
    }

    // MARK: Private

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var listPort

    private let logger = Logger(label: "k8smgr.app_shell.events_list")

    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?

    // MARK: Init

    public init() {}

    nonisolated deinit { pollingTask?.cancel() }

    // MARK: Intents

    /// Starts the 10-second polling loop for the given cluster.
    public func start(clusterId: ClusterId, namespace: String?) async {
        pollingTask?.cancel()
        await load(clusterId: clusterId, namespace: namespace)
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                await self?.load(clusterId: clusterId, namespace: namespace)
            }
        }
    }

    /// Stops polling (called when view disappears or tab changes).
    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: Private

    private func load(clusterId: ClusterId, namespace: String?) async {
        if case .idle = loadState { loadState = .loading }
        logger.info("events load cluster=\(clusterId.rawValue) ns=\(namespace ?? "<all>")")
        let gvk = GroupVersionKind.core("Event")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: namespace, clusterId: clusterId)
            let rows = items.map(Self.project)
            loadState = .success(rows)
        } catch {
            if loadState.value == nil {
                loadState = .failure(error)
            }
            logger.error("events load failed — \(error)")
        }
    }

    private static func project(_ item: ResourceListItem) -> ClusterEventRow {
        ClusterEventRow(
            id: item.uid,
            eventType: item.annotations["type"] ?? "Normal",
            reason: item.annotations["reason"] ?? "—",
            objectKind: item.annotations["involvedObject.kind"] ?? "—",
            objectName: item.annotations["involvedObject.name"] ?? item.name,
            source: item.annotations["source.component"] ?? "—",
            lastSeen: item.annotations["lastTimestamp"] ?? item.creationTimestamp,
            count: Int(item.annotations["count"] ?? "1") ?? 1,
            message: item.annotations["message"] ?? "—"
        )
    }
}

// MARK: - EventsListView

/// Displays Kubernetes Events with type/reason/object filter UI.
///
/// Polls every 10 s; no watch stream (high event cardinality per ADR-0050).
@MainActor
public struct EventsListView: View {

    let clusterId: ClusterId
    let namespace: String?

    @State private var viewModel = EventsListViewModel()

    public init(clusterId: ClusterId, namespace: String? = nil) {
        self.clusterId = clusterId
        self.namespace = namespace
    }

    public var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            eventsContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.start(clusterId: clusterId, namespace: namespace) }
        .onDisappear { viewModel.stop() }
    }

    // MARK: Private views

    private var filterBar: some View {
        HStack(spacing: 8) {
            Text("Events").font(.headline)
            if let count = viewModel.loadState.value?.count {
                Text("\(count)").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            typePicker
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary).imageScale(.small)
                TextField("Search", text: Binding(
                    get: { viewModel.filter.searchText },
                    set: { viewModel.filter.searchText = $0 }
                ))
                .textFieldStyle(.plain).font(.callout)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
            .frame(minWidth: 160, maxWidth: 240)
            if viewModel.loadState.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var typePicker: some View {
        Picker("Type", selection: Binding(
            get: { viewModel.filter.typeFilter },
            set: { viewModel.filter.typeFilter = $0 }
        )) {
            Text("All").tag(String?.none)
            Text("Warning").tag(String?.some("Warning"))
            Text("Normal").tag(String?.some("Normal"))
        }
        .pickerStyle(.menu)
        .frame(minWidth: 100)
    }

    @ViewBuilder
    private var eventsContent: some View {
        if viewModel.filteredRows.isEmpty && !viewModel.loadState.isLoading {
            ContentUnavailableView("No Events", systemImage: "calendar.badge.clock")
        } else {
            eventsTable
        }
    }

    private var eventsTable: some View {
        Table(viewModel.filteredRows) {
            TableColumn("Type") { row in
                HStack(spacing: 4) {
                    Image(systemName: row.isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(row.isWarning ? .orange : .blue)
                        .imageScale(.small)
                    Text(row.eventType).font(.caption)
                        .foregroundStyle(row.isWarning ? .orange : .blue)
                }
            }
            .width(80)
            TableColumn("Reason") { row in
                Text(row.reason).font(.caption.monospaced())
            }
            TableColumn("Object") { row in
                Text("\(row.objectKind)/\(row.objectName)").font(.caption)
            }
            TableColumn("Source") { row in
                Text(row.source).foregroundStyle(.secondary).font(.caption)
            }
            TableColumn("Last Seen") { row in
                Text(row.lastSeen).foregroundStyle(.secondary).font(.caption.monospaced())
            }
            TableColumn("Count") { row in
                Text("\(row.count)").foregroundStyle(.secondary).font(.caption.monospacedDigit())
            }
            .width(50)
            TableColumn("Message") { row in
                Text(row.message).font(.caption).lineLimit(2)
            }
        }
    }
}
