// Views/Resources/Config/PriorityClassesListViewModel.swift — app_shell bounded context
// DDD role: ViewModel (read model projection)
// ADR ref: ADR-0050 (resource navigation taxonomy)
// Note: PriorityClass is cluster-scoped — no namespace picker.

import Foundation
import Observation
import Dependencies
import ResourceBrowser
import SharedKernel

// MARK: - PriorityClassRow

/// Projected row for a PriorityClass resource in the list table.
public struct PriorityClassRow: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    /// Integer priority value.
    public let value: String
    /// Whether this is the global default priority class.
    public let globalDefault: String
    /// Short human-readable description from the manifest.
    public let description: String
    public let age: String
    public let listItem: ResourceListItem
}

// MARK: - PriorityClassesListViewModel

/// View model for the PriorityClasses list view (cluster-scoped).
@Observable
@MainActor
public final class PriorityClassesListViewModel {

    public var rows: [PriorityClassRow] = []
    public var selectedId: UUID?
    public var loadState: AsyncResource<Int> = .idle
    public var pendingDeleteRow: PriorityClassRow?
    public var showDeleteConfirm = false

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var resourceList

    public init() {}

    public func start(clusterId: ClusterId) async {
        await fetchRows(clusterId: clusterId)
    }

    public func reload(clusterId: ClusterId) async {
        await fetchRows(clusterId: clusterId)
    }

    public func requestDelete(_ row: PriorityClassRow) {
        pendingDeleteRow = row
        showDeleteConfirm = true
    }

    private func fetchRows(clusterId: ClusterId) async {
        loadState = .loading
        let gvk = GroupVersionKind(group: "scheduling.k8s.io", version: "v1", kind: "PriorityClass")
        do {
            let items = try await resourceList.list(gvk: gvk, namespace: nil, clusterId: clusterId)
            rows = items.map(PriorityClassRow.init)
            loadState = .success(rows.count)
        } catch {
            loadState = .failure(error)
        }
    }
}

private extension PriorityClassRow {
    init(_ item: ResourceListItem) {
        id = item.id
        name = item.name
        value = "—"
        globalDefault = "false"
        description = item.annotations["description"] ?? ""
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
