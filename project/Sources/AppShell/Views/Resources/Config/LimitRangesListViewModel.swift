// Views/Resources/Config/LimitRangesListViewModel.swift — app_shell bounded context
// DDD role: ViewModel (read model projection)
// ADR ref: ADR-0050 (resource navigation taxonomy)
// ADR ref: ADR-0069 (global namespace pill — actor subscription pattern)

import Foundation
import Observation
import Dependencies
import ResourceBrowser
import SharedKernel

// MARK: - LimitRangeRow

/// Projected row for a LimitRange resource in the list table.
public struct LimitRangeRow: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let namespace: String
    /// Number of limit entries (Container, Pod, PersistentVolumeClaim).
    public let constraintsCount: Int
    public let age: String
    public let listItem: ResourceListItem
}

// MARK: - LimitRangesListViewModel

/// View model for the LimitRanges list view.
@Observable
@MainActor
public final class LimitRangesListViewModel {

    public var rows: [LimitRangeRow] = []
    public var selectedId: UUID?
    public var loadState: AsyncResource<Int> = .idle
    public var namespace: String?
    public var pendingDeleteRow: LimitRangeRow?
    public var showDeleteConfirm = false

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var resourceList

    @ObservationIgnored
    @Dependency(\.namespaceFilter) private var namespaceFilter

    public init() {}

    /// Starts loading LimitRanges and subscribes to the global namespace filter
    /// so any chrome pill selection immediately re-fetches the list.
    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = await namespaceFilter.current(for: clusterId) ?? namespace
        await fetchRows(clusterId: clusterId)
        for await snapshot in namespaceFilter.stateStream(for: clusterId) {
            if snapshot.namespace == self.namespace { continue }
            self.namespace = snapshot.namespace
            await fetchRows(clusterId: clusterId)
        }
    }

    public func reload(clusterId: ClusterId) async {
        await fetchRows(clusterId: clusterId)
    }

    public func requestDelete(_ row: LimitRangeRow) {
        pendingDeleteRow = row
        showDeleteConfirm = true
    }

    private func fetchRows(clusterId: ClusterId) async {
        loadState = .loading
        let gvk = GroupVersionKind.core("LimitRange")
        do {
            let items = try await resourceList.list(gvk: gvk, namespace: namespace, clusterId: clusterId)
            rows = items.map(LimitRangeRow.init)
            loadState = .success(rows.count)
        } catch {
            loadState = .failure(error)
        }
    }
}

private extension LimitRangeRow {
    init(_ item: ResourceListItem) {
        id = item.id
        name = item.name
        namespace = item.namespace ?? ""
        constraintsCount = 0
        age = Self.ageLabel(seconds: item.ageSeconds)
        listItem = item
    }

    static func ageLabel(seconds: Int) -> String {
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }
}
