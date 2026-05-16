// Views/Resources/Config/HPAListViewModel.swift — app_shell bounded context
// DDD role: ViewModel (read model projection)
// ADR ref: ADR-0050 (resource navigation taxonomy)
// ADR ref: ADR-0069 (global namespace pill — actor subscription pattern)

import Foundation
import Observation
import Dependencies
import ResourceBrowser
import SharedKernel

// MARK: - HPARow

/// Projected row for a HorizontalPodAutoscaler resource in the list table.
public struct HPARow: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let namespace: String
    /// Scale target reference (e.g. "Deployment/my-app").
    public let reference: String
    /// Configured minimum replica count.
    public let minReplicas: String
    /// Configured maximum replica count.
    public let maxReplicas: String
    /// Current replica count.
    public let currentReplicas: String
    /// Human-readable metrics targets (e.g. "CPU: 80%").
    public let targets: String
    public let age: String
    public let listItem: ResourceListItem
}

// MARK: - HPAListViewModel

/// View model for the HorizontalPodAutoscalers list view.
@Observable
@MainActor
public final class HPAListViewModel {

    public var rows: [HPARow] = []
    public var selectedId: UUID?
    public var loadState: AsyncResource<Int> = .idle
    public var namespace: String?
    public var pendingDeleteRow: HPARow?
    public var showDeleteConfirm = false

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var resourceList

    @ObservationIgnored
    @Dependency(\.namespaceFilter) private var namespaceFilter

    public init() {}

    /// Starts loading HPAs and subscribes to the global namespace filter
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

    public func requestDelete(_ row: HPARow) {
        pendingDeleteRow = row
        showDeleteConfirm = true
    }

    private func fetchRows(clusterId: ClusterId) async {
        loadState = .loading
        let gvk = GroupVersionKind(group: "autoscaling", version: "v2", kind: "HorizontalPodAutoscaler")
        do {
            let items = try await resourceList.list(gvk: gvk, namespace: namespace, clusterId: clusterId)
            rows = items.map(HPARow.init)
            loadState = .success(rows.count)
        } catch {
            loadState = .failure(error)
        }
    }
}

private extension HPARow {
    init(_ item: ResourceListItem) {
        id = item.id
        name = item.name
        namespace = item.namespace ?? ""
        reference = "—"
        minReplicas = "—"
        maxReplicas = "—"
        currentReplicas = "—"
        targets = "—"
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
