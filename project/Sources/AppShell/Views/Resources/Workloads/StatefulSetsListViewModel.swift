// Views/Resources/Workloads/StatefulSetsListViewModel.swift — app_shell bounded context
// DDD role: ViewModel — StatefulSets resource list
// ADR ref: ADR-0050 (Onda 2 resource list views)

import Foundation
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.statefulsets_list")

// MARK: - StatefulSetRow

/// Table row projection for a single Kubernetes StatefulSet.
public struct StatefulSetRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let namespace: String
    /// `"readyReplicas/desiredReplicas"`
    public let ready: String
    public let age: String

    public init(id: String, name: String, namespace: String, ready: String, age: String) {
        self.id = id; self.name = name; self.namespace = namespace
        self.ready = ready; self.age = age
    }
}

// MARK: - StatefulSetsListViewModel

/// View model for the StatefulSets resource list view.
@Observable
@MainActor
public final class StatefulSetsListViewModel {

    public var rows: [StatefulSetRow] = []
    public var selectedId: String?
    public var namespace: String?
    public var loadState: AsyncResource<Int> = .idle
    public var searchText: String = ""

    public var filteredRows: [StatefulSetRow] {
        guard !searchText.isEmpty else { return rows }
        return rows.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.namespace.localizedCaseInsensitiveContains(searchText)
        }
    }

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var listPort

    public init() {}

    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = namespace
        await reload(clusterId: clusterId)
    }

    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        let gvk = GroupVersionKind(group: "apps", version: "v1", kind: "StatefulSet")
        log.info("statefulsets reload cluster=\(clusterId.rawValue)")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: namespace, clusterId: clusterId)
            rows = items.map(Self.project)
            loadState = .success(rows.count)
        } catch {
            log.error("statefulsets load failed — \(error)")
            loadState = .failure(error)
        }
    }

    public func confirmDelete(ids: Set<String>) {
        log.info("delete requested ids=\(ids.count) (stub)")
    }

    private static func project(_ item: ResourceListItem) -> StatefulSetRow {
        StatefulSetRow(
            id: item.uid, name: item.name, namespace: item.namespace ?? "",
            ready: "0/1",
            age: PodsListViewModel.ageString(seconds: item.ageSeconds)
        )
    }
}
