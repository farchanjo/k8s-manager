// ViewModels/ClusterListViewModel.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states)

import Foundation
import Dependencies
import ClusterConnectivity
import SharedKernel

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
        do {
            let path = KubeconfigPath("~/.kube/config")
            let config = try await kubeconfigLoader.load(from: path)
            let list = kubeconfigLoader.contexts(in: config)
            contexts = .success(list)
        } catch {
            contexts = .failure(error)
        }
    }

    /// Probes the health of the cluster referenced by `context`.
    ///
    /// - Parameter context: The kubeconfig context whose cluster is probed.
    public func probeHealth(for context: KubeconfigContext) async {
        healthByContext[context.name] = .loading
        do {
            let id = ClusterId(context.cluster)
            let status = try await kubernetesApi.probeHealth(clusterId: id)
            healthByContext[context.name] = .success(status)
        } catch {
            healthByContext[context.name] = .failure(error)
        }
    }
}
