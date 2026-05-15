// SwiftkubeClientAdapter.swift — infrastructure adapter
// Bounded context: cluster_connectivity (outbound port implementation)
// DDD role: Adapter (secondary — infrastructure)
// ADR ref: ADR-0002 (SwiftkubeClient adapter), ADR-0019 (Tier A libraries)
// Implements: KubernetesApiPort from ClusterConnectivity

import AsyncHTTPClient
import ClusterConnectivity
import Foundation
import Logging
import NIO
import SharedKernel
import SwiftkubeClient

// Note: NIOSSL and AuthInfo mapping live in ClusterParams.swift which does
// NOT import SwiftkubeClient, avoiding the AuthInfo name collision between
// ClusterConnectivity and SwiftkubeClient.KubeConfig.

// MARK: - SwiftkubeApiAdapter

/// Functional `KubernetesApiPort` adapter backed by `swiftkube/client`.
///
/// Supports bearer-token clusters for the initial vertical slice.
/// Client-certificate and exec-plugin auth are deferred to subsequent rounds
/// and guarded by `KubernetesApiError.authMethodNotYetImplemented`.
///
/// Thread safety: `struct` with value semantics. Each call instantiates and
/// shuts down a `KubernetesClient` actor — intentional for the first slice
/// to keep one client per cluster-identity bounded to the call lifetime.
public struct SwiftkubeApiAdapter: KubernetesApiPort {

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

    /// Creates the adapter with a caller-supplied resolver and an optional logger.
    ///
    /// - Parameters:
    ///   - resolver: Closure that maps a `ClusterId` to `ClusterParams`.
    ///     Provided by the composition root.
    ///   - logger: Optional logger; defaults to a no-op logger.
    public init(
        resolver: @escaping ClusterResolver,
        logger: Logger = SwiftkubeClient.loggingDisabled
    ) {
        self.resolver = resolver
        self.logger = logger
        // One thread is sufficient for a macOS desktop app.
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    // MARK: - KubernetesApiPort

    /// Probes the cluster's `/version` endpoint and maps the outcome to a
    /// `HealthStatus` value object.
    ///
    /// Mapping rules:
    /// - Successful `/version` response → `.reachable`
    /// - `statusError` HTTP 401 → `.unauthorized`
    /// - `statusError` HTTP 403 → `.forbidden`
    /// - `statusError` HTTP 5xx → `.degraded`
    /// - `clientError` / NIO / TLS error → `.unreachable`
    public func probeHealth(clusterId: ClusterId) async throws -> HealthStatus {
        let probeStart = Date()
        let probedAt = ISO8601DateFormatter().string(from: probeStart)

        do {
            let params = try await resolver(clusterId)
            let client = try makeClient(from: params)
            defer { try? client.syncShutdown() }

            _ = try await client.discoveryClient.serverVersion()

            let latency = Int(Date().timeIntervalSince(probeStart) * 1_000)
            return HealthStatus(
                clusterId: clusterId,
                probedAt: probedAt,
                state: .reachable,
                latencyMillis: latency
            )
        } catch let error as SwiftkubeClientError {
            return healthStatus(
                for: error,
                clusterId: clusterId,
                probedAt: probedAt,
                probeStart: probeStart
            )
        } catch let error as KubernetesApiError {
            throw error
        } catch {
            let latency = Int(Date().timeIntervalSince(probeStart) * 1_000)
            return HealthStatus(
                clusterId: clusterId,
                probedAt: probedAt,
                state: .unreachable,
                latencyMillis: latency,
                detail: error.localizedDescription
            )
        }
    }

    /// Fetches the server version string from the cluster's `/version` endpoint.
    ///
    /// - Returns: The `gitVersion` field from the version response
    ///   (e.g. `"v1.29.3+k3s1"`).
    public func serverVersion(clusterId: ClusterId) async throws -> String {
        let params = try await resolver(clusterId)
        let client = try makeClient(from: params)
        defer { try? client.syncShutdown() }

        let info = try await client.discoveryClient.serverVersion()
        return info.gitVersion
    }

    // MARK: - Private helpers

    /// Builds a `KubernetesClient` actor from resolved connection parameters.
    ///
    /// Auth and TLS mapping are delegated to `ClusterParams` extension methods
    /// (declared in `ClusterParams.swift`, which does not import SwiftkubeClient)
    /// to avoid the `AuthInfo` name collision.
    private func makeClient(from params: ClusterParams) throws -> KubernetesClient {
        let authentication: KubernetesClientAuthentication
        if let token = try params.bearerToken() {
            authentication = .bearer(token: token)
        } else {
            // Anonymous (no credential) — not a standard Kubernetes config,
            // but structurally valid for local dev clusters.
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

    /// Maps a `SwiftkubeClientError` to the appropriate `HealthStatus`.
    private func healthStatus(
        for error: SwiftkubeClientError,
        clusterId: ClusterId,
        probedAt: String,
        probeStart: Date
    ) -> HealthStatus {
        let latency = Int(Date().timeIntervalSince(probeStart) * 1_000)

        switch error {
        case .statusError(let status):
            let code = Int(status.code ?? 0)
            let detail = status.message
            let state = statusCodeToHealthState(code)
            return HealthStatus(
                clusterId: clusterId,
                probedAt: probedAt,
                state: state,
                latencyMillis: latency,
                detail: detail
            )
        case .clientError(let underlying):
            return HealthStatus(
                clusterId: clusterId,
                probedAt: probedAt,
                state: .unreachable,
                latencyMillis: latency,
                detail: "Transport error: \(underlying.localizedDescription)"
            )
        default:
            return HealthStatus(
                clusterId: clusterId,
                probedAt: probedAt,
                state: .unreachable,
                latencyMillis: latency,
                detail: "Unexpected client error: \(error)"
            )
        }
    }

    /// Maps an HTTP status code to the appropriate `HealthState`.
    ///
    /// Exposed as `internal` so the test target can reach it via
    /// `@testable import`.
    func statusCodeToHealthState(_ code: Int) -> HealthState {
        switch code {
        case 200 ..< 400: .reachable
        case 401: .unauthorized
        case 403: .forbidden
        case 500...: .degraded
        default: .unreachable
        }
    }
}

// MARK: - KubernetesApiError extension

public extension KubernetesApiError {
    /// The requested authentication method is not yet implemented in this
    /// adapter. Use bearer-token auth for the current vertical slice.
    static var authMethodNotYetImplemented: KubernetesApiError {
        .transportError(
            detail: "Auth method not yet implemented (only bearer-token is supported)"
        )
    }
}
