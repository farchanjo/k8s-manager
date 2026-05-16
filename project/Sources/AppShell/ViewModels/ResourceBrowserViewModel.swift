// ViewModels/ResourceBrowserViewModel.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states),
//          ADR-0013 (kind catalogue)

import Foundation
import Observation
import Dependencies
import Logging
import ClusterConnectivity
import ResourceBrowser
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.resource_browser")

// MARK: - ResourceBrowserViewModel

/// View model for the Kubernetes resource browser screen.
///
/// Owned by `ResourceBrowserView`. Drives paginated listing of resources for a
/// selected kind and optional namespace filter. All mutations run on the
/// `MainActor` so SwiftUI observation coalesces updates without data races.
@Observable
@MainActor
public final class ResourceBrowserViewModel {

    // MARK: State

    /// The currently selected Kubernetes kind name (e.g. `"Pod"`, `"Deployment"`).
    public var selectedKind: String = "Pod"

    /// Namespace filter applied to namespaced list requests. Empty means all namespaces.
    public var namespace: String = ""

    /// The currently selected list item, shown in the detail panel.
    public var selectedItem: ResourceListItem?

    /// Lifecycle state of the resource list load operation.
    public var resources: AsyncResource<[ResourceListItem]> = .idle

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var resourceList

    @ObservationIgnored
    @Dependency(\.kubeconfigLoader) private var kubeconfigLoader

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Fetches the resource list for the given kind and namespace.
    ///
    /// - Parameters:
    ///   - kind: The Kubernetes kind name (e.g. `"Pod"`).
    ///   - namespace: Namespace filter. `nil` or empty lists across all namespaces.
    public func load(kind: String, namespace: String?) async {
        selectedKind = kind
        resources = .loading
        let ns = namespace.flatMap { $0.isEmpty ? nil : $0 }
        log.info("load start kind=\(kind) namespace=\(ns ?? "<all>")")
        do {
            let clusterId = try await resolveActiveClusterId()
            let gvk = gvkFor(kind: kind)
            let items = try await resourceList.list(gvk: gvk, namespace: ns, clusterId: clusterId)
            log.info("load OK kind=\(kind) count=\(items.count)")
            resources = .success(items)
        } catch {
            log.error("load FAILED kind=\(kind) — \(error)")
            resources = .failure(error)
        }
    }

    // MARK: Private helpers — context resolution

    /// Loads `~/.kube/config` and returns the active cluster's `ClusterId`.
    ///
    /// - Throws: `ResourceListError.transportError` when no active context is set.
    private func resolveActiveClusterId() async throws -> ClusterId {
        let config = try await kubeconfigLoader.load(from: KubeconfigPath("~/.kube/config"))
        guard let ctx = kubeconfigLoader.activeContext(in: config) else {
            throw ResourceListError.transportError(detail: "No active Kubernetes context")
        }
        log.info("active context=\(ctx.name) cluster=\(ctx.cluster)")
        return ClusterId(ctx.cluster)
    }

    /// Selects a list item to display in the detail panel.
    ///
    /// - Parameter item: The row the user tapped, or `nil` to deselect.
    public func select(_ item: ResourceListItem?) {
        selectedItem = item
        log.info("select name=\(item?.name ?? "<none>")")
    }

    // MARK: Private helpers

    /// Resolves the GVK for the picker kind names supported by the UI.
    ///
    /// Falls back to a core/v1 GVK using the raw kind string so unknown picker
    /// values degrade gracefully rather than crash.
    private func gvkFor(kind: String) -> GroupVersionKind {
        switch kind {
        case "Deployment":  return GroupVersionKind(group: "apps", version: "v1", kind: kind)
        case "Ingress":     return GroupVersionKind(group: "networking.k8s.io", version: "v1", kind: kind)
        default:            return GroupVersionKind.core(kind)
        }
    }
}
