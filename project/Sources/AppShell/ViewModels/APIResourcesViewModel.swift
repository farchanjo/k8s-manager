// ViewModels/APIResourcesViewModel.swift — app_shell bounded context
// DDD role: ViewModel — API resource discovery browser
// ADR ref: ADR-0050 (cluster operations, Onda 2), ADR-0034 (state-driven UI)

import Foundation
import Observation
import Logging
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.api_resources")

// MARK: - APIResourcesViewModel

/// View model for the API Resources browser tab.
///
/// Aggregates `APIResource` rows from all server groups discovered via the
/// `KubernetesApiDiscoveryPort`. Provides a client-side search filter so
/// the user can narrow the table without a round trip.
///
/// All mutations are `@MainActor`-isolated; `@Observable` drives SwiftUI
/// observation without `@Published` boilerplate.
@Observable
@MainActor
public final class APIResourcesViewModel {

    // MARK: State

    /// Lifecycle state of the full resource discovery load.
    public var resources: AsyncResource<[APIResource]> = .idle

    /// Text typed in the search bar. Drives `filteredResources` reactively.
    public var searchQuery: String = ""

    /// Subset of `resources.value` matching `searchQuery`.
    public var filteredResources: [APIResource] {
        guard let all = resources.value else { return [] }
        guard !searchQuery.isEmpty else { return all }
        return all.filter { $0.matches(query: searchQuery) }
    }

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads the API resource list for `clusterId` on first call (`.idle` gate).
    ///
    /// Subsequent calls are no-ops; use `reload(clusterId:)` to force a refresh.
    public func start(clusterId: ClusterId) async {
        guard resources.isIdle else { return }
        await fetch(clusterId: clusterId)
    }

    /// Forces a fresh discovery load regardless of current state.
    public func reload(clusterId: ClusterId) async {
        await fetch(clusterId: clusterId)
    }

    // MARK: Private

    private func fetch(clusterId: ClusterId) async {
        resources = .loading
        log.info("fetch start clusterId=\(clusterId.rawValue)")
        do {
            let list = try await loadResources(clusterId: clusterId)
            let sorted = list.sorted { $0.kind < $1.kind }
            log.info("fetch OK count=\(sorted.count)")
            resources = .success(sorted)
        } catch {
            log.error("fetch FAILED — \(error)")
            resources = .failure(error)
        }
    }

    /// Performs the actual discovery call.
    ///
    /// In Onda 2 this returns a hardcoded stub that exercises the full UI path
    /// without a live cluster. Onda 3+ replaces the body with a real port call.
    private func loadResources(clusterId: ClusterId) async throws -> [APIResource] {
        // TODO(Onda-3): Replace stub with KubernetesApiDiscoveryPort call.
        try await Task.sleep(for: .milliseconds(200))
        return Self.stubResources()
    }

    // MARK: Stub data (Onda 2 placeholder)

    private static func stubResources() -> [APIResource] {
        [
            APIResource(
                group: "", version: "v1", kind: "Pod",
                plural: "pods", shortNames: ["po"],
                isNamespaced: true,
                verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
            ),
            APIResource(
                group: "", version: "v1", kind: "Service",
                plural: "services", shortNames: ["svc"],
                isNamespaced: true,
                verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
            ),
            APIResource(
                group: "apps", version: "v1", kind: "Deployment",
                plural: "deployments", shortNames: ["deploy"],
                isNamespaced: true,
                verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
            ),
            APIResource(
                group: "apps", version: "v1", kind: "DaemonSet",
                plural: "daemonsets", shortNames: ["ds"],
                isNamespaced: true,
                verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
            ),
            APIResource(
                group: "apps", version: "v1", kind: "StatefulSet",
                plural: "statefulsets", shortNames: ["sts"],
                isNamespaced: true,
                verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
            ),
            APIResource(
                group: "batch", version: "v1", kind: "Job",
                plural: "jobs", shortNames: [],
                isNamespaced: true,
                verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
            ),
            APIResource(
                group: "networking.k8s.io", version: "v1", kind: "Ingress",
                plural: "ingresses", shortNames: ["ing"],
                isNamespaced: true,
                verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
            ),
            APIResource(
                group: "", version: "v1", kind: "Namespace",
                plural: "namespaces", shortNames: ["ns"],
                isNamespaced: false,
                verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
            ),
            APIResource(
                group: "", version: "v1", kind: "Node",
                plural: "nodes", shortNames: ["no"],
                isNamespaced: false,
                verbs: ["get", "list", "watch", "update", "patch"]
            ),
            APIResource(
                group: "rbac.authorization.k8s.io", version: "v1", kind: "ClusterRole",
                plural: "clusterroles", shortNames: [],
                isNamespaced: false,
                verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
            ),
        ]
    }
}
