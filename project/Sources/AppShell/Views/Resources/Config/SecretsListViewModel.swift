// Views/Resources/Config/SecretsListViewModel.swift — app_shell bounded context
// DDD role: ViewModel (read model projection)
// ADR ref: ADR-0050 (resource navigation taxonomy), ADR-0034 (state-driven UI)

import Foundation
import Observation
import Dependencies
import ResourceBrowser
import SharedKernel

// MARK: - SecretRow

/// Projected row for a Secret resource in the list table.
public struct SecretRow: Identifiable, Sendable {
    /// Stable row identifier derived from the underlying `ResourceListItem`.
    public let id: UUID
    /// Secret name.
    public let name: String
    /// Namespace the Secret belongs to.
    public let namespace: String
    /// Kubernetes secret type (e.g. `Opaque`, `kubernetes.io/tls`).
    public let type: String
    /// Number of data keys in the Secret.
    public let dataCount: Int
    /// Human-readable age string.
    public let age: String
    /// Underlying list item for context menu actions.
    public let listItem: ResourceListItem
}

// MARK: - SecretsListViewModel

/// View model for the Secrets list view.
///
/// Fetches `Secret` resources from the Kubernetes API and projects them
/// into `SecretRow` values suitable for table display.
@Observable
@MainActor
public final class SecretsListViewModel {

    // MARK: State

    /// Projected rows populated after a successful fetch.
    public var rows: [SecretRow] = []
    /// Currently selected row id.
    public var selectedId: UUID?
    /// Lifecycle state of the fetch operation.
    public var loadState: AsyncResource<Int> = .idle
    /// Namespace filter; `nil` lists across all namespaces.
    public var namespace: String?
    /// Row targeted for the reveal-data modal.
    public var revealRow: SecretRow?
    /// Controls the reveal-data sheet.
    public var showRevealSheet = false
    /// Confirmation target for the delete dialog.
    public var pendingDeleteRow: SecretRow?
    /// Controls the delete confirmation alert.
    public var showDeleteConfirm = false

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var resourceList

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Starts loading Secrets for the given cluster and optional namespace.
    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = namespace
        await fetchRows(clusterId: clusterId)
    }

    /// Reloads using the last known cluster state.
    public func reload(clusterId: ClusterId) async {
        await fetchRows(clusterId: clusterId)
    }

    /// Opens the reveal-data sheet for the selected row.
    public func revealData(_ row: SecretRow) {
        revealRow = row
        showRevealSheet = true
    }

    /// Marks a row as pending deletion.
    public func requestDelete(_ row: SecretRow) {
        pendingDeleteRow = row
        showDeleteConfirm = true
    }

    // MARK: Private

    private func fetchRows(clusterId: ClusterId) async {
        loadState = .loading
        let gvk = GroupVersionKind.core("Secret")
        do {
            let items = try await resourceList.list(
                gvk: gvk, namespace: namespace, clusterId: clusterId
            )
            rows = items.map(SecretRow.init)
            loadState = .success(rows.count)
        } catch {
            loadState = .failure(error)
        }
    }
}

// MARK: - SecretRow init from ResourceListItem

private extension SecretRow {
    init(_ item: ResourceListItem) {
        id = item.id
        name = item.name
        namespace = item.namespace ?? ""
        type = item.annotations["type"] ?? "Opaque"
        dataCount = 0
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
