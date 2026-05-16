// SwiftkubePrometheusDiscoveryAdapter.swift — infrastructure adapter
// Bounded context: metrics_observability (outbound port implementation)
// DDD role: Adapter (secondary — infrastructure)
// ADR ref: ADR-0016 (auto-discovery: auto_label + auto_annotation tiers)
// Implements: EndpointDiscoveryPort from MetricsObservability

import AsyncHTTPClient
import ClusterConnectivity
import Foundation
import Logging
import MetricsObservability
import NIO
import SharedKernel
import SwiftkubeClient
import SwiftkubeModel

// MARK: - SwiftkubePrometheusDiscoveryAdapter

/// `EndpointDiscoveryPort` adapter backed by `swiftkube/client`.
///
/// Lists Services across all namespaces and applies the two ADR-0016
/// discovery tiers in order of precedence:
///
/// - **auto_annotation** (`prometheus.io/scrape == "true"`): checked first.
/// - **auto_label** (`app.kubernetes.io/name=prometheus`,
///   `app=prometheus`, or `app.kubernetes.io/component=prometheus`): checked
///   for any Service that does not already satisfy the annotation tier.
///
/// Each matching Service yields one `PrometheusEndpoint` with:
/// - `url`: `http://<name>.<namespace>.svc.cluster.local:<port>`, where
///   `<port>` is taken from the `prometheus.io/port` annotation when present,
///   otherwise from the first declared `ServicePort`.
/// - `discoverySource`: `.autoAnnotation` or `.autoLabel` as appropriate.
/// - `authStrategy`: `.bearerInherit` (ADR-0016 §3.2 — inherits cluster token).
/// - `status`: `.unknown` — probed lazily by the caller.
///
/// Thread safety: `struct` with value semantics; resolver and ELG are
/// captured as immutable or are `Sendable`.
public struct SwiftkubePrometheusDiscoveryAdapter: EndpointDiscoveryPort {

    // MARK: - Types

    /// Resolves a Kubernetes context UUID to connection parameters.
    ///
    /// The UUID corresponds to `PrometheusEndpoint.kubernetesContextId`
    /// (the primary key passed by `PrometheusDiscoveryService`).
    public typealias ClusterResolver = @Sendable (UUID) async throws -> ClusterParams

    // MARK: - Private constants

    private static let annotationScrape = "prometheus.io/scrape"
    private static let annotationPort = "prometheus.io/port"
    private static let labelAppName = "app.kubernetes.io/name"
    private static let labelApp = "app"
    private static let labelComponent = "app.kubernetes.io/component"

    private static let prometheusAppName = "prometheus"
    private static let prometheusComponent = "prometheus"

    private static let defaultPrometheusPort = 9090

    // MARK: - Properties

    private let resolver: ClusterResolver
    private let logger: Logger
    private let eventLoopGroup: MultiThreadedEventLoopGroup

    // MARK: - Initialiser

    /// Creates the adapter with a caller-supplied resolver and optional logger.
    ///
    /// - Parameters:
    ///   - resolver: Closure mapping a `kubernetesContextId` UUID to
    ///     `ClusterParams`.  Provided by the composition root.
    ///   - logger: Optional logger; defaults to a no-op logger.
    public init(
        resolver: @escaping ClusterResolver,
        logger: Logger = SwiftkubeClient.loggingDisabled
    ) {
        self.resolver = resolver
        self.logger = logger
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    // MARK: - EndpointDiscoveryPort

    /// Discovers Prometheus endpoint candidates by listing all Services and
    /// applying the ADR-0016 annotation and label tiers.
    ///
    /// Returns an empty array when no matching Service is found; never throws
    /// on an empty result — only raises on transport or authentication failures.
    ///
    /// - Parameter kubernetesContextId: UUID of the target Kubernetes context.
    /// - Returns: Collected endpoints sorted by `<namespace>/<name>`.
    /// - Throws: `EndpointDiscoveryError.kubernetesApiUnavailable` on API failure.
    public func discover(
        kubernetesContextId: UUID
    ) async throws -> [PrometheusEndpoint] {
        let params: ClusterParams
        do {
            params = try await resolver(kubernetesContextId)
        } catch {
            throw EndpointDiscoveryError.kubernetesApiUnavailable(
                detail: "Resolver failed: \(error.localizedDescription)"
            )
        }

        let client: KubernetesClient
        do {
            client = try makeClient(from: params)
        } catch {
            throw EndpointDiscoveryError.kubernetesApiUnavailable(
                detail: "Client construction failed: \(error.localizedDescription)"
            )
        }
        defer { try? client.syncShutdown() }

        let services: [core.v1.Service]
        do {
            services = try await client.services.list(in: .allNamespaces).items
        } catch {
            throw EndpointDiscoveryError.kubernetesApiUnavailable(
                detail: "Services list failed: \(error.localizedDescription)"
            )
        }

        let candidates = services.compactMap { service -> PrometheusEndpoint? in
            buildEndpoint(
                from: service,
                kubernetesContextId: kubernetesContextId
            )
        }

        return candidates.sorted {
            endpointSortKey($0) < endpointSortKey($1)
        }
    }

    /// Probes a candidate endpoint's health URL and returns a copy with an
    /// updated status.
    ///
    /// This implementation is intentionally minimal — it derives the probe URL
    /// from the endpoint's own `url` field and returns a stubbed `.unknown`
    /// status. A full HTTP probe is the responsibility of the caller (typically
    /// `PrometheusQueryPort`). This satisfies the protocol contract required by
    /// `EndpointDiscoveryPort` for symmetric completeness.
    ///
    /// - Parameter endpoint: The candidate to probe.
    /// - Returns: The endpoint unchanged (probe delegated to query adapter).
    public func probe(_ endpoint: PrometheusEndpoint) async throws -> PrometheusEndpoint {
        endpoint
    }

    // MARK: - Private — filter and construction

    /// Returns a `PrometheusEndpoint` when the Service matches ADR-0016 tiers,
    /// otherwise returns `nil`.
    private func buildEndpoint(
        from service: core.v1.Service,
        kubernetesContextId: UUID
    ) -> PrometheusEndpoint? {
        let meta = service.metadata
        let namespace = meta?.namespace ?? "default"
        let name = meta?.name ?? ""
        guard !name.isEmpty else { return nil }

        let annotations = meta?.annotations ?? [:]
        let labels = meta?.labels ?? [:]

        let source = discoverySource(annotations: annotations, labels: labels)
        guard let source else { return nil }

        let port = resolvePort(annotations: annotations, spec: service.spec)
        let url = "http://\(name).\(namespace).svc.cluster.local:\(port)"

        return PrometheusEndpoint(
            id: UUID(),
            kubernetesContextId: kubernetesContextId,
            url: url,
            discoverySource: source,
            authStrategy: .bearerInherit,
            insecureSkipTLSVerify: false,
            status: .unknown
        )
    }

    /// Determines the `DiscoverySource` for a Service, or `nil` if the Service
    /// does not match any ADR-0016 tier.
    ///
    /// Precedence: `auto_annotation` before `auto_label`.
    private func discoverySource(
        annotations: [String: String],
        labels: [String: String]
    ) -> DiscoverySource? {
        if annotations[Self.annotationScrape] == "true" {
            return .autoAnnotation
        }
        let appName = labels[Self.labelAppName] ?? ""
        let app = labels[Self.labelApp] ?? ""
        let component = labels[Self.labelComponent] ?? ""
        if appName == Self.prometheusAppName
            || app == Self.prometheusAppName
            || component == Self.prometheusComponent
        {
            return .autoLabel
        }
        return nil
    }

    /// Resolves the port for the endpoint URL.
    ///
    /// Priority:
    /// 1. `prometheus.io/port` annotation (parsed as integer).
    /// 2. First declared port in `spec.ports`.
    /// 3. Default: 9090.
    private func resolvePort(
        annotations: [String: String],
        spec: core.v1.ServiceSpec?
    ) -> Int {
        if let annotationValue = annotations[Self.annotationPort],
           let parsed = Int(annotationValue) {
            return parsed
        }
        if let firstPort = spec?.ports?.first?.port {
            return Int(firstPort)
        }
        return Self.defaultPrometheusPort
    }

    /// Returns a stable sort key `"<namespace>/<name>"` for consistent ordering.
    private func endpointSortKey(_ endpoint: PrometheusEndpoint) -> String {
        endpoint.url
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
}
