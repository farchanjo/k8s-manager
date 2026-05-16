// Views/Resources/Workloads/ReplicationControllersListViewModel.swift — app_shell bounded context
// DDD role: ViewModel — ReplicationControllers resource list
// ADR ref: ADR-0050 (Onda 2 resource list views)

import Foundation
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.replication_controllers_list")

// MARK: - ReplicationControllerRow

/// Table row projection for a single Kubernetes ReplicationController.
public struct ReplicationControllerRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let namespace: String
    public let desired: Int
    public let current: Int
    public let ready: Int
    public let age: String

    public init(
        id: String, name: String, namespace: String,
        desired: Int, current: Int, ready: Int, age: String
    ) {
        self.id = id; self.name = name; self.namespace = namespace
        self.desired = desired; self.current = current; self.ready = ready; self.age = age
    }
}

// MARK: - ReplicationControllersListViewModel

/// View model for the ReplicationControllers resource list view.
@Observable
@MainActor
public final class ReplicationControllersListViewModel {

    public var rows: [ReplicationControllerRow] = []
    public var selectedId: String?
    public var namespace: String?
    public var loadState: AsyncResource<Int> = .idle
    public var searchText: String = ""

    public var filteredRows: [ReplicationControllerRow] {
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
        let gvk = GroupVersionKind.core("ReplicationController")
        log.info("replication controllers reload cluster=\(clusterId.rawValue)")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: namespace, clusterId: clusterId)
            rows = items.map(Self.project)
            loadState = .success(rows.count)
        } catch {
            log.error("replication controllers load failed — \(error)")
            loadState = .failure(error)
        }
    }

    public func confirmDelete(ids: Set<String>) {
        log.info("delete requested ids=\(ids.count) (stub)")
    }

    private static func project(_ item: ResourceListItem) -> ReplicationControllerRow {
        let isReady = item.status.lowercased() == "running"
        return ReplicationControllerRow(
            id: item.uid, name: item.name, namespace: item.namespace ?? "",
            desired: 1, current: 1, ready: isReady ? 1 : 0,
            age: PodsListViewModel.ageString(seconds: item.ageSeconds)
        )
    }
}
