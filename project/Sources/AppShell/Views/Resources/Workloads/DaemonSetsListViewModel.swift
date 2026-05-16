// Views/Resources/Workloads/DaemonSetsListViewModel.swift — app_shell bounded context
// DDD role: ViewModel — DaemonSets resource list
// ADR ref: ADR-0050 (Onda 2 resource list views)

import Foundation
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.daemonsets_list")

// MARK: - DaemonSetRow

/// Table row projection for a single Kubernetes DaemonSet.
public struct DaemonSetRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let namespace: String
    public let desired: Int
    public let current: Int
    public let ready: Int
    public let upToDate: Int
    public let available: Int
    public let age: String

    public init(
        id: String, name: String, namespace: String,
        desired: Int, current: Int, ready: Int,
        upToDate: Int, available: Int, age: String
    ) {
        self.id = id; self.name = name; self.namespace = namespace
        self.desired = desired; self.current = current; self.ready = ready
        self.upToDate = upToDate; self.available = available; self.age = age
    }
}

// MARK: - DaemonSetsListViewModel

/// View model for the DaemonSets resource list view.
@Observable
@MainActor
public final class DaemonSetsListViewModel {

    public var rows: [DaemonSetRow] = []
    public var selectedId: String?
    public var namespace: String?
    public var loadState: AsyncResource<Int> = .idle
    public var searchText: String = ""

    public var filteredRows: [DaemonSetRow] {
        guard !searchText.isEmpty else { return rows }
        return rows.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.namespace.localizedCaseInsensitiveContains(searchText)
        }
    }

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var listPort

    @ObservationIgnored
    @Dependency(\.namespaceFilter) private var namespaceFilter

    public init() {}

    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = await namespaceFilter.current(for: clusterId) ?? namespace
        await reload(clusterId: clusterId)
        for await snapshot in namespaceFilter.stateStream(for: clusterId) {
            if snapshot.namespace == self.namespace { continue }
            self.namespace = snapshot.namespace
            await reload(clusterId: clusterId)
        }
    }

    public func reload(clusterId: ClusterId) async {
        let port = listPort
        let ns = namespace
        let gvk = GroupVersionKind(group: "apps", version: "v1", kind: "DaemonSet")
        log.info("daemonsets reload cluster=\(clusterId.rawValue)")
        await AsyncLoader.run(
            setLoading: { self.loadState = .loading },
            operation: { try await port.list(gvk: gvk, namespace: ns, clusterId: clusterId) },
            onSuccess: { items in
                self.rows = items.map(Self.project)
                self.loadState = .success(self.rows.count)
            },
            onFailure: { error in
                log.error("daemonsets load failed — \(error)")
                self.loadState = .failure(error)
            }
        )
    }

    public func confirmDelete(ids: Set<String>) {
        log.info("delete requested ids=\(ids.count) (stub)")
    }

    private static func project(_ item: ResourceListItem) -> DaemonSetRow {
        DaemonSetRow(
            id: item.uid, name: item.name, namespace: item.namespace ?? "",
            desired: 1, current: 1, ready: item.status.lowercased() == "running" ? 1 : 0,
            upToDate: 1, available: 1,
            age: PodsListViewModel.ageString(seconds: item.ageSeconds)
        )
    }
}
