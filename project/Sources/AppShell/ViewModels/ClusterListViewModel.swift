// ViewModels/ClusterListViewModel.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states)

import Foundation
import Dependencies
import Logging
import ClusterConnectivity
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.cluster_list")

// MARK: - ClusterListViewModel

/// View model for the cluster list screen.
///
/// Owned by `ClusterListView`. Drives kubeconfig loading and per-context health
/// probes. All mutations happen on the `MainActor` so SwiftUI observation
/// coalesces updates without data races.
@Observable
@MainActor
public final class ClusterListViewModel {

    // MARK: State

    /// Lifecycle state of the kubeconfig load operation.
    public var contexts: AsyncResource<[KubeconfigContext]> = .idle

    /// Per-context health probe state, keyed by `KubeconfigContext.name`.
    public var healthByContext: [String: AsyncResource<HealthStatus>] = [:]

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubeconfigLoader) private var kubeconfigLoader

    @ObservationIgnored
    @Dependency(\.kubernetesApi) private var kubernetesApi

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads the kubeconfig from `~/.kube/config` and populates `contexts`.
    public func loadKubeconfig() async {
        contexts = .loading
        log.info("loadKubeconfig start")
        do {
            let path = KubeconfigPath("~/.kube/config")
            let config = try await kubeconfigLoader.load(from: path)
            let list = kubeconfigLoader.contexts(in: config)
            log.info("loadKubeconfig OK — contexts=\(list.count) clusters=\(config.clusters.count) users=\(config.users.count) current=\(config.currentContext ?? "<nil>")")
            for c in list {
                log.info("  context name=\(c.name) cluster=\(c.cluster) user=\(c.user) ns=\(c.namespace)")
            }
            contexts = .success(list)
        } catch {
            log.error("loadKubeconfig FAILED — \(error)")
            contexts = .failure(error)
        }
    }

    /// Probes the health of the cluster referenced by `context`.
    ///
    /// - Parameter context: The kubeconfig context whose cluster is probed.
    public func probeHealth(for context: KubeconfigContext) async {
        healthByContext[context.name] = .loading
        log.info("probeHealth start context=\(context.name) cluster=\(context.cluster)")
        do {
            let id = ClusterId(context.cluster)
            let status = try await kubernetesApi.probeHealth(clusterId: id)
            log.info("probeHealth result state=\(status.state) latencyMs=\(status.latencyMillis) detail=\(status.detail ?? "<nil>")")
            healthByContext[context.name] = .success(status)
        } catch {
            log.error("probeHealth THROWN — \(error)")
            healthByContext[context.name] = .failure(error)
        }
    }
}
