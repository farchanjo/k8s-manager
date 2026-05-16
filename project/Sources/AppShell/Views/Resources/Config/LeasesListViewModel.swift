// Views/Resources/Config/LeasesListViewModel.swift — app_shell bounded context
// DDD role: ViewModel (read model projection)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import Foundation
import Observation
import Dependencies
import ResourceBrowser
import SharedKernel

// MARK: - LeaseRow

/// Projected row for a Lease resource in the list table.
public struct LeaseRow: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let namespace: String
    /// Identity of the current lease holder.
    public let holder: String
    public let age: String
    public let listItem: ResourceListItem
}

// MARK: - LeasesListViewModel

/// View model for the Leases list view.
@Observable
@MainActor
public final class LeasesListViewModel {

    public var rows: [LeaseRow] = []
    public var selectedId: UUID?
    public var loadState: AsyncResource<Int> = .idle
    public var namespace: String?
    public var pendingDeleteRow: LeaseRow?
    public var showDeleteConfirm = false

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var resourceList

    public init() {}

    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = namespace
        await fetchRows(clusterId: clusterId)
    }

    public func reload(clusterId: ClusterId) async {
        await fetchRows(clusterId: clusterId)
    }

    public func requestDelete(_ row: LeaseRow) {
        pendingDeleteRow = row
        showDeleteConfirm = true
    }

    private func fetchRows(clusterId: ClusterId) async {
        loadState = .loading
        let gvk = GroupVersionKind(group: "coordination.k8s.io", version: "v1", kind: "Lease")
        do {
            let items = try await resourceList.list(gvk: gvk, namespace: namespace, clusterId: clusterId)
            rows = items.map(LeaseRow.init)
            loadState = .success(rows.count)
        } catch {
            loadState = .failure(error)
        }
    }
}

private extension LeaseRow {
    init(_ item: ResourceListItem) {
        id = item.id
        name = item.name
        namespace = item.namespace ?? ""
        holder = item.annotations["holderIdentity"] ?? "—"
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
