// SwiftkubeResourceListAdapter.swift — infrastructure adapter
// Bounded context: resource_browser (outbound port implementation)
// DDD role: Adapter (secondary — infrastructure)
// ADR ref: ADR-0002 (SwiftkubeClient adapter), ADR-0013 (kind catalogue)
// Implements: KubernetesResourceListPort from ResourceBrowser

import AsyncHTTPClient
import ClusterConnectivity
import Foundation
import Logging
import NIO
import ResourceBrowser
import SharedKernel
import SwiftkubeClient
import SwiftkubeModel

// Disambiguate the two GroupVersionKind types visible in this module.
// ResourceBrowser.GroupVersionKind is the domain value object used as output.
// SwiftkubeModel.GroupVersionKind is the library type — not used in output.
public typealias DomainGVK = ResourceBrowser.GroupVersionKind

// MARK: - SwiftkubeResourceListAdapter

/// Functional `KubernetesResourceListPort` adapter backed by `swiftkube/client`.
///
/// Supports the seven core kinds from ADR-0013: Pod, Deployment, Service,
/// ConfigMap, Secret, Namespace, and Ingress. Each call creates and shuts
/// down a short-lived `KubernetesClient` actor — intentional for the first
/// vertical slice to keep one client per call lifetime.
///
/// Thread safety: `struct` with value semantics. Resolver and ELG are
/// captured by value or reference respectively; both are `Sendable`.
public struct SwiftkubeResourceListAdapter: KubernetesResourceListPort {

    // MARK: - Types

    /// Resolves a `ClusterId` to the raw connection parameters needed to build
    /// a `KubernetesClient`. The composition root wires this to a
    /// `KubeconfigLoaderPort` lookup.
    public typealias ClusterResolver = @Sendable (ClusterId) async throws -> ClusterParams

    // MARK: - Properties

    private let resolver: ClusterResolver
    private let logger: Logger
    private let eventLoopGroup: MultiThreadedEventLoopGroup

    // MARK: - Initialiser

    /// Creates the adapter with a caller-supplied resolver and optional logger.
    ///
    /// - Parameters:
    ///   - resolver: Closure that maps a `ClusterId` to `ClusterParams`.
    ///   - logger: Optional logger; defaults to a no-op logger.
    public init(
        resolver: @escaping ClusterResolver,
        logger: Logger = SwiftkubeClient.loggingDisabled
    ) {
        self.resolver = resolver
        self.logger = logger
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    // MARK: - KubernetesResourceListPort

    /// Lists resources for the given GVK, optionally scoped to a namespace.
    ///
    /// Supported GVKs: Pod, Service, ConfigMap, Secret, Namespace (core/v1);
    /// Deployment (apps/v1); Ingress (networking.k8s.io/v1).
    /// Unknown GVKs throw `ResourceListError.unknownGVK`.
    public func list(
        gvk: DomainGVK,
        namespace: String?,
        contextId: UUID
    ) async throws -> [ResourceListItem] {
        let params = try await resolveParams(contextId: contextId)
        let client = try makeClient(from: params)
        defer { try? client.syncShutdown() }
        return try await fetchList(gvk: gvk, namespace: namespace, client: client)
    }

    /// Fetches a single resource plus its recent events as a `ResourceDetail`.
    ///
    /// Events are fetched in-namespace and filtered by `involvedObject.uid`.
    /// Up to 50 events are kept, ordered by `lastTimestamp` descending.
    public func get(
        gvk: DomainGVK,
        name: String,
        namespace: String?,
        contextId: UUID
    ) async throws -> ResourceDetail {
        let params = try await resolveParams(contextId: contextId)
        let client = try makeClient(from: params)
        defer { try? client.syncShutdown() }
        return try await fetchDetail(gvk: gvk, name: name, namespace: namespace, client: client)
    }

    // MARK: - Private — resolver

    private func resolveParams(contextId: UUID) async throws -> ClusterParams {
        let clusterId = ClusterId(contextId.uuidString)
        return try await resolver(clusterId)
    }

    // MARK: - Private — client factory

    private func makeClient(from params: ClusterParams) throws -> KubernetesClient {
        let authentication: KubernetesClientAuthentication
        if let token = try params.bearerToken() {
            authentication = .bearer(token: token)
        } else {
            authentication = .bearer(token: "")
        }

        let config = KubernetesClientConfig(
            masterURL: params.server,
            namespace: "default",
            authentication: authentication,
            trustRoots: try params.trustRoots(),
            insecureSkipTLSVerify: params.insecureSkipTLSVerify,
            timeout: .init(connect: .seconds(10), read: .seconds(30)),
            redirectConfiguration: .follow(max: 5, allowCycles: false)
        )

        return KubernetesClient(
            config: config,
            provider: .shared(eventLoopGroup),
            logger: logger
        )
    }

    // MARK: - Private — list dispatch

    private func fetchList(
        gvk: DomainGVK,
        namespace: String?,
        client: KubernetesClient
    ) async throws -> [ResourceListItem] {
        let ns = namespaceSelector(from: namespace)

        switch (gvk.group, gvk.kind) {
        case ("", "Pod"):
            let items = try await client.pods.list(in: ns).items
            return items.map { mapToListItem($0.metadata, gvk: gvk, statusText: podStatusText($0)) }
        case ("", "Service"):
            let items = try await client.services.list(in: ns).items
            return items.map { mapToListItem($0.metadata, gvk: gvk, statusText: "") }
        case ("", "ConfigMap"):
            let items = try await client.configMaps.list(in: ns).items
            return items.map { mapToListItem($0.metadata, gvk: gvk, statusText: "") }
        case ("", "Secret"):
            let items = try await client.secrets.list(in: ns).items
            return items.map { mapToListItem($0.metadata, gvk: gvk, statusText: "") }
        case ("", "Namespace"):
            let items = try await client.namespaces.list().items
            return items.map { mapToListItem($0.metadata, gvk: gvk, statusText: $0.status?.phase ?? "") }
        case ("apps", "Deployment"):
            let items = try await client.appsV1.deployments.list(in: ns).items
            return items.map { mapToListItem($0.metadata, gvk: gvk, statusText: deploymentStatusText($0)) }
        case ("networking.k8s.io", "Ingress"):
            let items = try await client.networkingV1.ingresses.list(in: ns).items
            return items.map { mapToListItem($0.metadata, gvk: gvk, statusText: "") }
        default:
            throw ResourceListError.unknownGVK(gvk)
        }
    }

    // MARK: - Private — get dispatch

    private func fetchDetail(
        gvk: DomainGVK,
        name: String,
        namespace: String?,
        client: KubernetesClient
    ) async throws -> ResourceDetail {
        let ns = namespaceSelector(from: namespace)

        switch (gvk.group, gvk.kind) {
        case ("", "Pod"):
            let resource = try await client.pods.get(in: ns, name: name)
            let conditions = (resource.status?.conditions ?? []).map { mapPodCondition($0) }
            let events = try await fetchEvents(client: client, ns: ns, uid: resource.metadata?.uid)
            let item = mapToListItem(resource.metadata, gvk: gvk, statusText: podStatusText(resource))
            return ResourceDetail(listItem: item, rawJSON: encodeToJSON(resource), conditions: conditions, recentEvents: events)
        case ("", "Service"):
            let resource = try await client.services.get(in: ns, name: name)
            let conditions = (resource.status?.conditions ?? []).map { mapMetaCondition($0) }
            let events = try await fetchEvents(client: client, ns: ns, uid: resource.metadata?.uid)
            let item = mapToListItem(resource.metadata, gvk: gvk, statusText: "")
            return ResourceDetail(listItem: item, rawJSON: encodeToJSON(resource), conditions: conditions, recentEvents: events)
        case ("", "ConfigMap"):
            let resource = try await client.configMaps.get(in: ns, name: name)
            let events = try await fetchEvents(client: client, ns: ns, uid: resource.metadata?.uid)
            let item = mapToListItem(resource.metadata, gvk: gvk, statusText: "")
            return ResourceDetail(listItem: item, rawJSON: encodeToJSON(resource), recentEvents: events)
        case ("", "Secret"):
            let resource = try await client.secrets.get(in: ns, name: name)
            let events = try await fetchEvents(client: client, ns: ns, uid: resource.metadata?.uid)
            let item = mapToListItem(resource.metadata, gvk: gvk, statusText: "")
            return ResourceDetail(listItem: item, rawJSON: encodeToJSON(resource), recentEvents: events)
        case ("", "Namespace"):
            let resource = try await client.namespaces.get(name: name)
            let conditions = (resource.status?.conditions ?? []).map { mapNamespaceCondition($0) }
            let events = try await fetchEvents(client: client, ns: ns, uid: resource.metadata?.uid)
            let item = mapToListItem(resource.metadata, gvk: gvk, statusText: resource.status?.phase ?? "")
            return ResourceDetail(listItem: item, rawJSON: encodeToJSON(resource), conditions: conditions, recentEvents: events)
        case ("apps", "Deployment"):
            let resource = try await client.appsV1.deployments.get(in: ns, name: name)
            let conditions = (resource.status?.conditions ?? []).map { mapDeploymentCondition($0) }
            let events = try await fetchEvents(client: client, ns: ns, uid: resource.metadata?.uid)
            let item = mapToListItem(resource.metadata, gvk: gvk, statusText: deploymentStatusText(resource))
            return ResourceDetail(listItem: item, rawJSON: encodeToJSON(resource), conditions: conditions, recentEvents: events)
        case ("networking.k8s.io", "Ingress"):
            let resource = try await client.networkingV1.ingresses.get(in: ns, name: name)
            let events = try await fetchEvents(client: client, ns: ns, uid: resource.metadata?.uid)
            let item = mapToListItem(resource.metadata, gvk: gvk, statusText: "")
            return ResourceDetail(listItem: item, rawJSON: encodeToJSON(resource), recentEvents: events)
        default:
            throw ResourceListError.unknownGVK(gvk)
        }
    }

    // MARK: - Private — event fetch

    private func fetchEvents(
        client: KubernetesClient,
        ns: NamespaceSelector,
        uid: String?
    ) async throws -> [EventSummary] {
        guard let uid else { return [] }
        let all = try await client.events.list(in: ns)
        let formatter = ISO8601DateFormatter()
        return all.items
            .filter { $0.involvedObject.uid == uid }
            .compactMap { mapEvent($0, formatter: formatter) }
            .sorted { $0.lastTimestamp > $1.lastTimestamp }
            .prefix(50)
            .map { $0 }
    }

    // MARK: - Private — list item mapper

    private func mapToListItem(
        _ meta: meta.v1.ObjectMeta?,
        gvk: DomainGVK,
        statusText: String
    ) -> ResourceListItem {
        let now = Date()
        let creationDate = meta?.creationTimestamp ?? now
        let formatter = ISO8601DateFormatter()
        let age = max(0, Int(now.timeIntervalSince(creationDate)))

        return ResourceListItem(
            id: UUIDv7.generate(now: now),
            gvk: gvk,
            namespace: meta?.namespace,
            name: meta?.name ?? "",
            uid: meta?.uid ?? "",
            creationTimestamp: formatter.string(from: creationDate),
            status: statusText,
            ageSeconds: age,
            labels: meta?.labels ?? [:],
            annotations: meta?.annotations ?? [:]
        )
    }

    // MARK: - Private — namespace selector helper

    private func namespaceSelector(from namespace: String?) -> NamespaceSelector {
        namespace.map { .namespace($0) } ?? .allNamespaces
    }

    // MARK: - Private — status text helpers

    private func podStatusText(_ pod: core.v1.Pod) -> String {
        pod.status?.phase ?? "Unknown"
    }

    private func deploymentStatusText(_ dep: apps.v1.Deployment) -> String {
        guard let status = dep.status else { return "Unknown" }
        let ready = status.readyReplicas ?? 0
        let total = status.replicas ?? 0
        return "\(ready)/\(total)"
    }

    // MARK: - Private — condition mappers

    private func mapPodCondition(_ c: core.v1.PodCondition) -> StatusCondition {
        let formatter = ISO8601DateFormatter()
        return StatusCondition(
            conditionType: c.type,
            status: conditionStatus(c.status),
            reason: c.reason ?? "",
            message: c.message ?? "",
            lastTransitionTime: c.lastTransitionTime.map { formatter.string(from: $0) } ?? ""
        )
    }

    private func mapMetaCondition(_ c: meta.v1.Condition) -> StatusCondition {
        let formatter = ISO8601DateFormatter()
        return StatusCondition(
            conditionType: c.type,
            status: conditionStatus(c.status),
            reason: c.reason,
            message: c.message,
            lastTransitionTime: formatter.string(from: c.lastTransitionTime)
        )
    }

    private func mapNamespaceCondition(_ c: core.v1.NamespaceCondition) -> StatusCondition {
        StatusCondition(
            conditionType: c.type,
            status: conditionStatus(c.status),
            reason: c.reason ?? "",
            message: c.message ?? "",
            lastTransitionTime: ""
        )
    }

    private func mapDeploymentCondition(_ c: apps.v1.DeploymentCondition) -> StatusCondition {
        let formatter = ISO8601DateFormatter()
        return StatusCondition(
            conditionType: c.type,
            status: conditionStatus(c.status),
            reason: c.reason ?? "",
            message: c.message ?? "",
            lastTransitionTime: c.lastTransitionTime.map { formatter.string(from: $0) } ?? ""
        )
    }

    private func conditionStatus(_ raw: String) -> StatusCondition.ConditionStatus {
        switch raw {
        case "True": return .true
        case "False": return .false
        default: return .unknown
        }
    }

    // MARK: - Private — event mapper

    private func mapEvent(
        _ event: core.v1.Event,
        formatter: ISO8601DateFormatter
    ) -> EventSummary? {
        guard let reason = event.reason, let message = event.message else { return nil }
        let ts = event.lastTimestamp.map { formatter.string(from: $0) } ?? ""
        let eventType: EventSummary.EventType = event.type == "Warning" ? .warning : .normal
        return EventSummary(
            reason: reason,
            message: message,
            eventType: eventType,
            count: Int(event.count ?? 1),
            lastTimestamp: ts
        )
    }

    // MARK: - Private — JSON encoder

    private func encodeToJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }
}
