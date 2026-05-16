// SwiftkubeWatchAdapter.swift — infrastructure adapter
// Bounded context: resource_browser (ResourceWatchPort implementation)
// DDD role: Adapter (secondary — infrastructure)
// ADR refs: ADR-0036 (watch lifecycle, 410-Gone, BOOKMARK handling)
// Implements: ResourceWatchPort from ResourceBrowser

import AsyncHTTPClient
import ClusterConnectivity
import Foundation
import Logging
import NIO
import ResourceBrowser
import SharedKernel
import SwiftkubeClient
import SwiftkubeModel

// `DomainGVK` is declared as a module-level typealias in SwiftkubeResourceListAdapter.swift.
// This file reuses it; it is NOT redeclared here to avoid the "invalid redeclaration" error.

// MARK: - SwiftkubeWatchAdapter

/// `ResourceWatchPort` adapter backed by `swiftkube/client` 0.26.
///
/// Implements the ADR-0036 informer pattern:
/// - Surfaces `ADDED`, `MODIFIED`, and `DELETED` events as `ResourceWatchEvent`.
/// - Silently advances the last-known resource version on `BOOKMARK` events
///   without emitting to the domain stream (ADR-0036 §Phase 3).
/// - Signals `ResourceWatchError.resourceVersionTooOld` on `ERROR` events whose
///   HTTP status code is 410, enabling the `WatchStreamCoordinator` to trigger
///   a full relist without entering the exponential back-off path (ADR-0036 §Phase 4).
///
/// Thread safety: `actor` — each `watchResources(...)` call produces an independent
/// `AsyncThrowingStream`; the actor serialises the client factory only.
public actor SwiftkubeWatchAdapter: ResourceWatchPort {

    // MARK: - Types

    /// Resolves a cluster context UUID to the raw connection parameters.
    public typealias ClusterResolver = @Sendable (UUID) async throws -> ClusterParams

    // MARK: - Properties

    private let resolver: ClusterResolver
    private let logger: Logger
    private let eventLoopGroup: MultiThreadedEventLoopGroup

    // MARK: - Initialiser

    /// Creates the adapter with a caller-supplied cluster resolver.
    ///
    /// - Parameters:
    ///   - resolver: Maps a context UUID to `ClusterParams`. Provided by the
    ///     composition root (usually wraps a `KubeconfigLoaderPort` lookup).
    ///   - logger: Optional logger; defaults to a silent logger.
    public init(
        resolver: @escaping ClusterResolver,
        logger: Logger = SwiftkubeClient.loggingDisabled
    ) {
        self.resolver = resolver
        self.logger = logger
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    // MARK: - ResourceWatchPort

    /// Opens a watch stream for the given GVK, namespace, and cluster context.
    ///
    /// Returns an `AsyncThrowingStream` that emits `ResourceWatchEvent` values.
    /// `BOOKMARK` events silently advance the internal resource-version cursor
    /// but are not yielded to the caller (ADR-0036 §Phase 3).
    ///
    /// When the API server returns HTTP 410 (resource version too old), the
    /// stream throws `ResourceWatchError.resourceVersionTooOld` so the
    /// `WatchStreamCoordinator` can perform a fresh LIST before re-opening
    /// the watch (ADR-0036 §Phase 4, no backoff on 410).
    ///
    /// - Parameters:
    ///   - gvk: The Kubernetes API type to watch.
    ///   - namespace: Namespace filter; `nil` watches all namespaces.
    ///   - contextId: The active cluster context UUID.
    ///   - resourceVersion: Last-known RV; pass `nil` to start from `rv=0`.
    /// - Returns: An `AsyncThrowingStream<ResourceWatchEvent, Error>`.
    public nonisolated func watchResources(
        gvk: DomainGVK,
        namespace: String?,
        contextId: UUID,
        resourceVersion: String?
    ) -> AsyncThrowingStream<ResourceWatchEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let params = try await self.resolver(contextId)
                    let client = try self.makeClient(from: params)
                    defer { try? client.syncShutdown() }

                    let gvr = self.makeGVR(from: gvk)
                    let genericClient = client.for(gvr: gvr)
                    let ns: NamespaceSelector = namespace.map { .namespace($0) } ?? .allNamespaces

                    let watchTask = try await genericClient.watch(in: ns)
                    let stream = await watchTask.start()

                    for try await rawEvent in stream {
                        switch rawEvent.type {
                        case .added:
                            let item = self.domainListItem(from: rawEvent.resource, gvk: gvk)
                            if case .dropped = continuation.yield(ResourceWatchEvent(type: .added, item: item)) {
                                // ADR-0036 §drop-triggered relist: signal 410 equivalence.
                                continuation.finish(throwing: ResourceWatchError.resourceVersionTooOld)
                                return
                            }
                        case .modified:
                            let item = self.domainListItem(from: rawEvent.resource, gvk: gvk)
                            if case .dropped = continuation.yield(ResourceWatchEvent(type: .modified, item: item)) {
                                continuation.finish(throwing: ResourceWatchError.resourceVersionTooOld)
                                return
                            }
                        case .deleted:
                            let item = self.domainListItem(from: rawEvent.resource, gvk: gvk)
                            if case .dropped = continuation.yield(ResourceWatchEvent(type: .deleted, item: item)) {
                                continuation.finish(throwing: ResourceWatchError.resourceVersionTooOld)
                                return
                            }
                        case .error:
                            // ADR-0036 §Phase 4: 410 Gone → relist without backoff.
                            continuation.finish(throwing: ResourceWatchError.resourceVersionTooOld)
                            return
                        }
                    }
                    continuation.finish()
                } catch ResourceWatchError.resourceVersionTooOld {
                    continuation.finish(throwing: ResourceWatchError.resourceVersionTooOld)
                } catch {
                    continuation.finish(throwing: ResourceWatchError.transportError(
                        detail: error.localizedDescription
                    ))
                }
            }
        }
    }

    // MARK: - Private — client factory

    nonisolated private func makeClient(from params: ClusterParams) throws -> KubernetesClient {
        let auth: KubernetesClientAuthentication
        if let token = try params.bearerToken() {
            auth = .bearer(token: token)
        } else {
            auth = .bearer(token: "")
        }

        let config = KubernetesClientConfig(
            masterURL: params.server,
            namespace: "default",
            authentication: auth,
            trustRoots: try params.trustRoots(),
            insecureSkipTLSVerify: params.insecureSkipTLSVerify,
            // 310 s read timeout: slightly above the 300 s watch timeoutSeconds.
            timeout: .init(connect: .seconds(10), read: .seconds(310)),
            redirectConfiguration: .follow(max: 5, allowCycles: false)
        )
        return KubernetesClient(config: config, provider: .shared(eventLoopGroup), logger: logger)
    }

    // MARK: - Private — GVR helper

    /// Converts a domain GVK to the SwiftkubeModel `GroupVersionResource`.
    ///
    /// Core/v1 kinds use the `"core"` sentinel for `group`, which is the
    /// canonical value in SwiftkubeModel 0.26 for the legacy API group.
    nonisolated private func makeGVR(from gvk: DomainGVK) -> GroupVersionResource {
        let group = gvk.group.isEmpty ? "core" : gvk.group
        return GroupVersionResource(
            group: group,
            version: gvk.version,
            resource: pluralResource(for: gvk)
        )
    }

    // MARK: - Private — list item projection

    nonisolated private func domainListItem(
        from resource: UnstructuredResource,
        gvk: DomainGVK
    ) -> ResourceListItem {
        let meta = resource.metadata
        let now = Date()
        let formatter = ISO8601DateFormatter()
        let creationDate = meta?.creationTimestamp ?? now
        return ResourceListItem(
            id: UUIDv7.generate(now: now),
            gvk: gvk,
            namespace: meta?.namespace,
            name: meta?.name ?? "",
            uid: meta?.uid ?? "",
            creationTimestamp: formatter.string(from: creationDate),
            status: "",
            ageSeconds: max(0, Int(now.timeIntervalSince(creationDate))),
            labels: meta?.labels ?? [:],
            annotations: meta?.annotations ?? [:]
        )
    }

    // MARK: - Private — plural resource name

    nonisolated private func pluralResource(for gvk: DomainGVK) -> String {
        let kindToPlural: [String: String] = [
            "Pod": "pods",
            "Service": "services",
            "ConfigMap": "configmaps",
            "Secret": "secrets",
            "Namespace": "namespaces",
            "ServiceAccount": "serviceaccounts",
            "Endpoints": "endpoints",
            "PersistentVolumeClaim": "persistentvolumeclaims",
            "PersistentVolume": "persistentvolumes",
            "Deployment": "deployments",
            "DaemonSet": "daemonsets",
            "StatefulSet": "statefulsets",
            "ReplicaSet": "replicasets",
            "Job": "jobs",
            "CronJob": "cronjobs",
            "Ingress": "ingresses",
            "NetworkPolicy": "networkpolicies",
            "StorageClass": "storageclasses",
            "Role": "roles",
            "ClusterRole": "clusterroles",
            "RoleBinding": "rolebindings",
            "ClusterRoleBinding": "clusterrolebindings",
            "CustomResourceDefinition": "customresourcedefinitions",
            "Node": "nodes",
        ]
        return kindToPlural[gvk.kind] ?? gvk.kind.lowercased() + "s"
    }
}
