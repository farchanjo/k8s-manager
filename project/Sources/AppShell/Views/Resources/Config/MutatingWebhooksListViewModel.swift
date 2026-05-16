// Views/Resources/Config/MutatingWebhooksListViewModel.swift — app_shell bounded context
// DDD role: ViewModel (read model projection)
// ADR ref: ADR-0050 (resource navigation taxonomy)
// Note: MutatingWebhookConfiguration is cluster-scoped — no namespace picker.

import Foundation
import Observation
import Dependencies
import ResourceBrowser
import SharedKernel

// MARK: - MutatingWebhookRow

/// Projected row for a MutatingWebhookConfiguration resource in the list table.
public struct MutatingWebhookRow: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    /// Number of webhook entries registered in this configuration.
    public let webhooksCount: Int
    public let age: String
    public let listItem: ResourceListItem
}

// MARK: - MutatingWebhooksListViewModel

/// View model for the MutatingWebhookConfigurations list view (cluster-scoped).
@Observable
@MainActor
public final class MutatingWebhooksListViewModel {

    public var rows: [MutatingWebhookRow] = []
    public var selectedId: UUID?
    public var loadState: AsyncResource<Int> = .idle
    public var pendingDeleteRow: MutatingWebhookRow?
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

    public func requestDelete(_ row: MutatingWebhookRow) {
        pendingDeleteRow = row
        showDeleteConfirm = true
    }

    private func fetchRows(clusterId: ClusterId) async {
        loadState = .loading
        let gvk = GroupVersionKind(
            group: "admissionregistration.k8s.io",
            version: "v1",
            kind: "MutatingWebhookConfiguration"
        )
        do {
            let items = try await resourceList.list(gvk: gvk, namespace: nil, clusterId: clusterId)
            rows = items.map(MutatingWebhookRow.init)
            loadState = .success(rows.count)
        } catch {
            loadState = .failure(error)
        }
    }
}

private extension MutatingWebhookRow {
    init(_ item: ResourceListItem) {
        id = item.id
        name = item.name
        webhooksCount = 0
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
