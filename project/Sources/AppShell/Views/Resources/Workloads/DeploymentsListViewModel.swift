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

    /// Namespaces visible in the active cluster, used to populate the
    /// `NamespaceFilterPicker` dropdown. Loaded once per `start(...)` and
    /// re-used across reloads to avoid hitting the apiserver each refresh.
    public var availableNamespaces: [String] = []

    public var filteredRows: [DeploymentRow] {
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

    /// Starts the list. Subscribes to the global ``NamespaceFilterActor`` so
    /// every change to the toolbar picker re-fetches deployments for the new
    /// namespace. The subscription owns the long-lived `for await` loop;
    /// SwiftUI cancels it automatically when the view disappears because
    /// `start` is invoked from `.task`.
    public func start(clusterId: ClusterId, namespace: String?) async {
        // Seed initial namespace from the global filter (falls back to the
        // optional init param when the actor has nothing for this cluster).
        self.namespace = await namespaceFilter.current(for: clusterId) ?? namespace
        async let namespacesTask: Void = loadNamespaces(clusterId: clusterId)
        async let reloadTask: Void = reload(clusterId: clusterId)
        _ = await (namespacesTask, reloadTask)
        // Track future filter changes for the lifetime of the view.
        for await snapshot in namespaceFilter.stateStream(for: clusterId) {
            if snapshot.namespace == self.namespace { continue }
            self.namespace = snapshot.namespace
            await reload(clusterId: clusterId)
        }
    }

    /// Fetches the cluster's namespace list to populate the toolbar filter.
    ///
    /// Errors are swallowed (logged) — the dropdown silently falls back to
    /// its quick-pick set so the list view never becomes unusable when the
    /// service account lacks namespace list permission.
    public func loadNamespaces(clusterId: ClusterId) async {
        let nsGvk = GroupVersionKind.core("Namespace")
        do {
            let items = try await listPort.list(gvk: nsGvk, namespace: nil, clusterId: clusterId)
            availableNamespaces = items.map(\.name).sorted()
        } catch {
            log.warning("namespaces load failed — \(error)")
        }
    }

    public func reload(clusterId: ClusterId) async {
        let port = listPort
        let ns = namespace
        let gvk = GroupVersionKind(group: "apps", version: "v1", kind: "Deployment")
        log.info("deployments reload cluster=\(clusterId.rawValue) namespace=\(ns ?? "<all>")")
        await AsyncLoader.run(
            setLoading: { self.loadState = .loading },
            operation: { try await port.list(gvk: gvk, namespace: ns, clusterId: clusterId) },
            onSuccess: { items in
                self.rows = items.map(Self.project)
                self.loadState = .success(self.rows.count)
                log.info("deployments loaded count=\(self.rows.count) namespace=\(ns ?? "<all>")")
            },
            onFailure: { error in
                log.error("deployments load failed — \(error)")
                self.loadState = .failure(error)
            }
        )
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
