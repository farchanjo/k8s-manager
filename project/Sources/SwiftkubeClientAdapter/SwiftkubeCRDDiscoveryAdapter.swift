// SwiftkubeCRDDiscoveryAdapter.swift — infrastructure adapter
// Bounded context: resource_browser (CRDDiscoveryPort implementation)
// DDD role: Adapter (secondary — infrastructure)
// ADR ref: ADR-0052 (custom resource discovery and rendering)
// Implements: CRDDiscoveryPort from ResourceBrowser

import AsyncHTTPClient
import ClusterConnectivity
import Foundation
import Logging
import NIO
import ResourceBrowser
import SharedKernel
import SwiftkubeClient
import SwiftkubeModel

// Note: `SwiftkubeModel` is intentionally NOT imported here.
// This avoids the `GroupVersionResource` name conflict between
// `SharedKernel.GroupVersionResource` (domain type) and
// `SwiftkubeModel.GroupVersionResource` (Kubernetes API model).
// All SwiftkubeModel types needed here (apiextensions.v1.*) are accessible
// through the transitive re-export from `SwiftkubeClient`.

// MARK: - SwiftkubeCRDDiscoveryAdapter

/// `CRDDiscoveryPort` adapter backed by `swiftkube/client` 0.26.
///
/// Lists `apiextensions.k8s.io/v1/CustomResourceDefinitions` and builds a
/// `CRDCatalog` by mapping each CRD's storage version spec into `CRDEntry`
/// and `PrinterColumn` domain types.
///
/// The watch path uses a list-plus-poll strategy: each call to
/// `watchCRDChanges` begins a fresh list at intervals; a proper
/// `AsyncThrowingStream` wraps the polling so callers get catalog snapshots.
///
/// Thread safety: `struct` with value semantics.
public struct SwiftkubeCRDDiscoveryAdapter: CRDDiscoveryPort {

    // MARK: - Types

    /// Resolves a `ClusterId` to the raw connection parameters.
    public typealias ClusterResolver = @Sendable (ClusterId) async throws -> ClusterParams

    // MARK: - Properties

    private let resolver: ClusterResolver
    private let logger: Logger

    // MARK: - Initialiser

    /// Creates the adapter with a caller-supplied resolver and optional logger.
    ///
    /// - Parameters:
    ///   - resolver: Maps a `ClusterId` to `ClusterParams`.
    ///   - logger: Optional logger; defaults to a silent logger.
    public init(
        resolver: @escaping ClusterResolver,
        logger: Logger = SwiftkubeClient.loggingDisabled
    ) {
        self.resolver = resolver
        self.logger = logger
    }

    // MARK: - CRDDiscoveryPort

    /// Lists all CRDs from `apiextensions.k8s.io/v1` and returns a snapshot.
    public func discoverCRDs(clusterId: ClusterId) async throws -> CRDCatalog {
        let params = try await resolver(clusterId)
        let client = try makeClient(from: params)
        defer { try? client.syncShutdown() }

        do {
            let list = try await client.apiExtensionsV1.customResourceDefinitions.list()
            return buildCatalog(from: list.items)
        } catch let error as SwiftkubeClientError {
            throw mapError(error)
        }
    }

    /// Emits a new `CRDCatalog` snapshot each time the CRD set changes.
    ///
    /// Polls at a 30-second interval by default. Terminates on resolver or
    /// transport error.
    public func watchCRDChanges(clusterId: ClusterId) -> AsyncThrowingStream<CRDCatalog, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var previousCatalog: CRDCatalog? = nil
                    while !Task.isCancelled {
                        let catalog = try await discoverCRDs(clusterId: clusterId)
                        if catalog != previousCatalog {
                            continuation.yield(catalog)
                            previousCatalog = catalog
                        }
                        try await Task.sleep(nanoseconds: 30_000_000_000)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
            provider: .shared(SharedNetworking.eventLoopGroup),
            logger: logger
        )
    }

    // MARK: - Private — catalog builder

    private func buildCatalog(
        from crds: [apiextensions.v1.CustomResourceDefinition]
    ) -> CRDCatalog {
        let now = ISO8601DateFormatter().string(from: Date())
        let entries = crds.compactMap(buildEntry).sorted { $0.displayName < $1.displayName }
        return CRDCatalog(entries: entries, lastUpdatedRFC3339: now)
    }

    private func buildEntry(
        from crd: apiextensions.v1.CustomResourceDefinition
    ) -> CRDEntry? {
        let spec = crd.spec
        guard let storageVersion = spec.versions.first(where: { $0.storage }) else {
            return nil
        }
        let gvr: CRDEntry.ID = GroupVersionResource(
            group: spec.group,
            version: storageVersion.name,
            resource: spec.names.plural
        )
        let columns = (storageVersion.additionalPrinterColumns ?? []).map(mapColumn)
        return CRDEntry(
            id: gvr,
            displayName: spec.names.kind,
            isNamespaced: spec.scope == "Namespaced",
            columns: columns,
            categories: spec.names.categories ?? []
        )
    }

    private func mapColumn(
        _ col: apiextensions.v1.CustomResourceColumnDefinition
    ) -> PrinterColumn {
        PrinterColumn(name: col.name, jsonPath: col.jsonPath, type: col.type)
    }

    // MARK: - Private — error mapping

    private func mapError(_ error: SwiftkubeClientError) -> CRDDiscoveryError {
        switch error {
        case .statusError(let status):
            let code = Int(status.code ?? 0)
            if code == 401 { return .unauthorized }
            return .transportError(detail: status.message ?? "HTTP \(code)")
        case .clientError(let underlying):
            return .transportError(detail: underlying.localizedDescription)
        default:
            return .transportError(detail: "\(error)")
        }
    }
}
