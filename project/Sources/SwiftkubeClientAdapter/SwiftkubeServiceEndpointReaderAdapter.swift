// SwiftkubeServiceEndpointReaderAdapter.swift — SwiftkubeClientAdapter
// DDD role: Adapter (secondary — outbound, infrastructure)
// Implements: ServiceEndpointReaderPort (PortForwarding)
// ADR ref: ADR-0007 (ServiceEndpointReaderPort live adapter)

import Foundation
import Logging
import PortForwarding
import SharedKernel
import SwiftkubeClient
import SwiftkubeModel

// MARK: - SwiftkubeServiceEndpointReaderAdapter

/// Resolves a Kubernetes Service to its backing ``PodTarget`` list by querying
/// the `discovery.k8s.io/v1/EndpointSlice` API for slices labelled
/// `kubernetes.io/service-name=<service>`.
///
/// The adapter requires both a ``ClusterResolver`` that maps a `ClusterId` to
/// raw connection parameters and a ``ClusterIdProvider`` closure that returns
/// the currently active cluster at call time. The composition root supplies the
/// provider from `ClusterStripActor` (or equivalent active-cluster tracker).
///
/// `conditions.ready == nil` is treated as `true` per the Kubernetes API
/// invariant documented in `EndpointConditions`.
public struct SwiftkubeServiceEndpointReaderAdapter: ServiceEndpointReaderPort {

    // MARK: - Types

    /// Resolves a `ClusterId` to raw connection parameters.
    public typealias ClusterResolver = @Sendable (ClusterId) async throws -> ClusterParams

    /// Returns the currently active `ClusterId`, or `nil` when no cluster is selected.
    public typealias ClusterIdProvider = @Sendable () async -> ClusterId?

    // MARK: - Properties

    private let resolver: ClusterResolver
    private let clusterIdProvider: ClusterIdProvider
    private let logger: Logger

    // MARK: - Initialiser

    /// Creates the adapter.
    ///
    /// - Parameters:
    ///   - resolver: Maps a `ClusterId` to `ClusterParams`. Provided by the composition root.
    ///   - clusterIdProvider: Returns the active `ClusterId` at call time.
    ///   - logger: Diagnostics destination; defaults to a no-op logger.
    public init(
        resolver: @escaping ClusterResolver,
        clusterIdProvider: @escaping ClusterIdProvider,
        logger: Logger = SwiftkubeClient.loggingDisabled
    ) {
        self.resolver = resolver
        self.clusterIdProvider = clusterIdProvider
        self.logger = logger
    }

    // MARK: - ServiceEndpointReaderPort

    /// Resolves the backing ``PodTarget`` list for a Kubernetes Service.
    ///
    /// Lists all `EndpointSlice` resources in `namespace` labelled with
    /// `kubernetes.io/service-name=<service>` and returns one `PodTarget`
    /// per ready endpoint address, using `targetRef.name` when present and
    /// falling back to the address string.
    public func resolveEndpoint(for service: String, namespace: String) async throws -> [PodTarget] {
        guard let clusterId = await clusterIdProvider() else {
            throw ServiceEndpointReaderError.apiError(
                statusCode: 0,
                detail: "No active cluster available"
            )
        }
        let client = try await makeClient(for: clusterId)
        defer { try? client.syncShutdown() }

        let ns = NamespaceSelector.namespace(namespace)
        let selector = LabelSelectorRequirement.eq(["kubernetes.io/service-name": service])
        do {
            let sliceList = try await client.discoveryV1.endpointSlices.list(
                in: ns,
                options: [.labelSelector(selector)]
            )
            let pods = readyPodTargets(from: sliceList.items, namespace: namespace)
            guard !pods.isEmpty else {
                throw ServiceEndpointReaderError.noReadyPodsFound(
                    service: service,
                    namespace: namespace
                )
            }
            logger.debug("serviceEndpointReader resolved service=\(service) ns=\(namespace) pods=\(pods.count)")
            return pods
        } catch let err as ServiceEndpointReaderError {
            throw err
        } catch let err as SwiftkubeClientError {
            throw mapSwiftkubeError(err, service: service, namespace: namespace)
        }
    }

    // MARK: - Private helpers

    private func readyPodTargets(
        from slices: [discovery.v1.EndpointSlice],
        namespace: String
    ) -> [PodTarget] {
        slices.flatMap { slice in
            slice.endpoints.compactMap { endpoint -> PodTarget? in
                guard isReady(endpoint.conditions) else { return nil }
                let podName = endpoint.targetRef?.name ?? endpoint.addresses.first ?? ""
                guard !podName.isEmpty else { return nil }
                return PodTarget(namespace: namespace, podName: podName)
            }
        }
    }

    /// `conditions.ready == nil` is treated as `true` per the Kubernetes spec.
    private func isReady(_ conditions: discovery.v1.EndpointConditions?) -> Bool {
        conditions?.ready ?? true
    }

    private func makeClient(for clusterId: ClusterId) async throws -> KubernetesClient {
        let params = try await resolver(clusterId)
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
            provider: .shared(SharedNetworking.eventLoopGroup),
            logger: logger
        )
    }

    private func mapSwiftkubeError(
        _ err: SwiftkubeClientError,
        service: String,
        namespace: String
    ) -> ServiceEndpointReaderError {
        switch err {
        case .statusError(let status):
            let code = Int(status.code ?? 0)
            if code == 404 {
                return .serviceNotFound(service: service, namespace: namespace)
            }
            return .apiError(statusCode: code, detail: status.message ?? "HTTP \(code)")
        case .clientError(let underlying):
            return .apiError(statusCode: 0, detail: underlying.localizedDescription)
        default:
            return .apiError(statusCode: 0, detail: String(describing: err))
        }
    }
}
