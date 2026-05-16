// Views/Resources/Workloads/DeploymentsListViewModel.swift — app_shell bounded context
// DDD role: ViewModel — Deployments resource list
// ADR ref: ADR-0050 (Onda 2 resource list views)

import Foundation
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.deployments_list")

// MARK: - DeploymentRow

/// Table row projection for a single Kubernetes Deployment.
public struct DeploymentRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let namespace: String
    /// `"readyReplicas/desiredReplicas"` — derived from status string.
    public let podsReady: String
    public let replicas: Int
    public let available: Int
    public let age: String

    public init(
        id: String, name: String, namespace: String,
        podsReady: String, replicas: Int, available: Int, age: String
    ) {
        self.id = id
        self.name = name
        self.namespace = namespace
        self.podsReady = podsReady
        self.replicas = replicas
        self.available = available
        self.age = age
    }
}

// MARK: - DeploymentsListViewModel

/// View model for the Deployments resource list view.
@Observable
@MainActor
public final class DeploymentsListViewModel {

    public var rows: [DeploymentRow] = []
    public var selectedId: String?
    public var namespace: String?
    public var loadState: AsyncResource<Int> = .idle
    public var searchText: String = ""

    public var filteredRows: [DeploymentRow] {
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
        let gvk = GroupVersionKind(group: "apps", version: "v1", kind: "Deployment")
        log.info("deployments reload cluster=\(clusterId.rawValue)")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: namespace, clusterId: clusterId)
            rows = items.map(Self.project)
            loadState = .success(rows.count)
        } catch {
            log.error("deployments load failed — \(error)")
            loadState = .failure(error)
        }
    }

    public func confirmDelete(ids: Set<String>) {
        log.info("delete requested ids=\(ids.count) (stub)")
    }

    private static func project(_ item: ResourceListItem) -> DeploymentRow {
        DeploymentRow(
            id: item.uid,
            name: item.name,
            namespace: item.namespace ?? "",
            podsReady: "0/1",
            replicas: 1,
            available: item.status.lowercased() == "running" ? 1 : 0,
            age: PodsListViewModel.ageString(seconds: item.ageSeconds)
        )
    }
}
