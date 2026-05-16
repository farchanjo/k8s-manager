// Views/Resources/Config/RuntimeClassesListViewModel.swift — app_shell bounded context
// DDD role: ViewModel (read model projection)
// ADR ref: ADR-0050 (resource navigation taxonomy)
// Note: RuntimeClass is cluster-scoped — no namespace picker.

import Foundation
import Observation
import Dependencies
import ResourceBrowser
import SharedKernel

// MARK: - RuntimeClassRow

/// Projected row for a RuntimeClass resource in the list table.
public struct RuntimeClassRow: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    /// Container runtime handler name (e.g. "runc", "kata").
    public let handler: String
    public let age: String
    public let listItem: ResourceListItem
}

// MARK: - RuntimeClassesListViewModel

/// View model for the RuntimeClasses list view (cluster-scoped).
@Observable
@MainActor
public final class RuntimeClassesListViewModel {

    public var rows: [RuntimeClassRow] = []
    public var selectedId: UUID?
    public var loadState: AsyncResource<Int> = .idle
    public var pendingDeleteRow: RuntimeClassRow?
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

    public func requestDelete(_ row: RuntimeClassRow) {
        pendingDeleteRow = row
        showDeleteConfirm = true
    }

    private func fetchRows(clusterId: ClusterId) async {
        loadState = .loading
        let gvk = GroupVersionKind(group: "node.k8s.io", version: "v1", kind: "RuntimeClass")
        do {
            let items = try await resourceList.list(gvk: gvk, namespace: nil, clusterId: clusterId)
            rows = items.map(RuntimeClassRow.init)
            loadState = .success(rows.count)
        } catch {
            loadState = .failure(error)
        }
    }
}

private extension RuntimeClassRow {
    init(_ item: ResourceListItem) {
        id = item.id
        name = item.name
        handler = item.annotations["handler"] ?? "—"
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
