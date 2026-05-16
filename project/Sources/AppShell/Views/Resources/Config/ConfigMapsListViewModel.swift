// Views/Resources/Config/ConfigMapsListViewModel.swift — app_shell bounded context
// DDD role: ViewModel (read model projection)
// ADR ref: ADR-0050 (resource navigation taxonomy), ADR-0034 (state-driven UI)

import Foundation
import Observation
import Dependencies
import ResourceBrowser
import SharedKernel

// MARK: - ConfigMapRow

/// Projected row for a ConfigMap resource in the list table.
public struct ConfigMapRow: Identifiable, Sendable {
    /// Stable row identifier derived from the underlying `ResourceListItem`.
    public let id: UUID
    /// ConfigMap name.
    public let name: String
    /// Namespace the ConfigMap belongs to.
    public let namespace: String
    /// Number of data keys in the ConfigMap.
    public let dataCount: Int
    /// Human-readable age string (e.g. "3d", "12h").
    public let age: String
    /// Underlying list item for context menu actions.
    public let listItem: ResourceListItem
}

// MARK: - ConfigMapsListViewModel

/// View model for the ConfigMaps list view.
///
/// Fetches `ConfigMap` resources from the Kubernetes API and projects them
/// into `ConfigMapRow` values suitable for table display.
@Observable
@MainActor
public final class ConfigMapsListViewModel {

    // MARK: State

    /// Projected rows populated after a successful fetch.
    public var rows: [ConfigMapRow] = []
    /// Currently selected row id, drives table selection.
    public var selectedId: UUID?
    /// Lifecycle state of the fetch operation.
    public var loadState: AsyncResource<Int> = .idle
    /// Namespace filter; `nil` lists across all namespaces.
    public var namespace: String?
    /// Confirmation target for the delete dialog.
    public var pendingDeleteRow: ConfigMapRow?
    /// Controls the delete confirmation alert.
    public var showDeleteConfirm = false

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var resourceList

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Starts loading ConfigMaps for the given cluster and optional namespace.
    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = namespace
        await fetchRows(clusterId: clusterId)
    }

    /// Reloads using the last known cluster id stored in the most recent row.
    public func reload(clusterId: ClusterId) async {
        await fetchRows(clusterId: clusterId)
    }

    /// Marks a row as pending deletion and shows the confirm dialog.
    public func requestDelete(_ row: ConfigMapRow) {
        pendingDeleteRow = row
        showDeleteConfirm = true
    }

    // MARK: Private

    private func fetchRows(clusterId: ClusterId) async {
        loadState = .loading
        let gvk = GroupVersionKind.core("ConfigMap")
        do {
            let items = try await resourceList.list(
                gvk: gvk, namespace: namespace, clusterId: clusterId
            )
            rows = items.map(ConfigMapRow.init)
            loadState = .success(rows.count)
        } catch {
            loadState = .failure(error)
        }
    }
}

// MARK: - ConfigMapRow init from ResourceListItem

private extension ConfigMapRow {
    init(_ item: ResourceListItem) {
        id = item.id
        name = item.name
        namespace = item.namespace ?? ""
        dataCount = Int(item.annotations["kubectl.kubernetes.io/last-applied-configuration"] != nil ? 1 : 0)
        age = Self.ageLabel(seconds: item.ageSeconds)
        listItem = item
    }

    static func ageLabel(seconds: Int) -> String {
        switch seconds {
        case ..<60:     return "\(seconds)s"
        case ..<3600:   return "\(seconds / 60)m"
        case ..<86400:  return "\(seconds / 3600)h"
        default:        return "\(seconds / 86400)d"
        }
    }
}
