// SwiftkubeRollbackLeaseAdapter.swift — SwiftkubeClientAdapter
// DDD role: Adapter (secondary — outbound, infrastructure)
// Implements: RollbackLeasePort (HelmManagement)
// ADR ref: ADR-0046 (Helm rollback Lease-based mutual exclusion)

import Foundation
import HelmManagement
import Logging
import SharedKernel
import SwiftkubeClient
import SwiftkubeModel

// MARK: - SwiftkubeRollbackLeaseAdapter

/// Kubernetes `coordination.k8s.io/v1/Lease` adapter implementing rollback
/// mutual exclusion per ADR-0046.
///
/// Acquisition protocol (three steps from ADR-0046 §Acquisition):
/// 1. GET the Lease. If absent, POST it with our `holderIdentity`.
/// 2. If found and stale (`renewTime + 60s < now`), conflict so caller retries.
/// 3. If found, live, and held by another identity, throw `.contention`.
///
/// Each call constructs a short-lived `KubernetesClient` (consistent with the
/// `SwiftkubeApiAdapter` per-call client pattern — ADR-0002). Clients are shut
/// down via `defer { try? client.syncShutdown() }`.
public struct SwiftkubeRollbackLeaseAdapter: RollbackLeasePort {

    // MARK: - Types

    /// Resolves a `ClusterId` to raw connection parameters.
    public typealias ClusterResolver = @Sendable (ClusterId) async throws -> ClusterParams

    // MARK: - Properties

    private let resolver: ClusterResolver
    private let logger: Logger

    // MARK: - Initialiser

    /// Creates the adapter with a cluster resolver and optional logger.
    ///
    /// - Parameters:
    ///   - resolver: Maps `ClusterId` to `ClusterParams`. Provided by the composition root.
    ///   - logger: Diagnostics destination; defaults to a no-op logger.
    public init(
        resolver: @escaping ClusterResolver,
        logger: Logger = SwiftkubeClient.loggingDisabled
    ) {
        self.resolver = resolver
        self.logger = logger
    }

    // MARK: - RollbackLeasePort

    /// Acquires a `coordination.k8s.io/v1/Lease` for the named release.
    ///
    /// On HTTP 409 Conflict the call throws `RollbackLeaseError.conflict`;
    /// the caller retries from the beginning per ADR-0046 §Acquisition.
    public func acquireLease(
        releaseName: String,
        namespace: String,
        holderIdentity: String,
        clusterId: ClusterId
    ) async throws -> RollbackLease {
        let client = try await makeClient(for: clusterId)
        defer { try? client.syncShutdown() }

        let leaseName = buildLeaseName(for: releaseName)
        let ns = NamespaceSelector.namespace(namespace)
        let now = Date()
        let nowString = formatISO8601(now)

        do {
            let existing = try await client.coordinationV1.leases.get(in: ns, name: leaseName)
            return try resolveContention(
                existing: existing,
                namespace: namespace,
                releaseName: releaseName,
                holderIdentity: holderIdentity,
                now: now,
                nowString: nowString
            )
        } catch let err as SwiftkubeClientError {
            if case .statusError(let status) = err, status.code == 404 {
                return try await postNewLease(
                    name: leaseName,
                    namespace: namespace,
                    ns: ns,
                    releaseName: releaseName,
                    holderIdentity: holderIdentity,
                    now: now,
                    nowString: nowString,
                    client: client
                )
            }
            throw mapError(err)
        }
    }

    /// Refreshes `renewTime` on an already-held Lease.
    ///
    /// Verifies `holderIdentity` matches before updating. If the Lease was
    /// overwritten, throws `RollbackLeaseError.stolen`.
    public func renewLease(
        _ lease: RollbackLease,
        clusterId: ClusterId
    ) async throws -> RollbackLease {
        let client = try await makeClient(for: clusterId)
        defer { try? client.syncShutdown() }

        let ns = NamespaceSelector.namespace(lease.namespace)
        let nowString = formatISO8601(Date())

        do {
            var existing = try await client.coordinationV1.leases.get(in: ns, name: lease.leaseName)
            guard existing.spec?.holderIdentity == lease.holderIdentity else {
                throw RollbackLeaseError.stolen
            }
            existing.spec?.renewTime = Date()
            let updated = try await client.coordinationV1.leases.update(inNamespace: ns, existing)
            return RollbackLease(
                namespace: lease.namespace,
                releaseName: lease.releaseName,
                holderIdentity: lease.holderIdentity,
                acquireTime: lease.acquireTime,
                renewTime: updated.spec?.renewTime.map(formatISO8601) ?? nowString
            )
        } catch let err as SwiftkubeClientError {
            if case .statusError(let status) = err, status.code == 409 {
                throw RollbackLeaseError.stolen
            }
            throw mapError(err)
        }
    }

    /// Deletes the Lease on rollback completion (success or failure).
    ///
    /// HTTP 404 is silently ignored — the Lease may have auto-expired.
    /// All other failures are surfaced but are non-fatal for callers.
    public func releaseLease(
        _ lease: RollbackLease,
        clusterId: ClusterId
    ) async throws {
        let client = try await makeClient(for: clusterId)
        defer { try? client.syncShutdown() }

        let ns = NamespaceSelector.namespace(lease.namespace)
        do {
            try await client.coordinationV1.leases.delete(inNamespace: ns, name: lease.leaseName)
        } catch let err as SwiftkubeClientError {
            if case .statusError(let status) = err, status.code == 404 {
                return
            }
            throw mapError(err)
        }
    }

    // MARK: - Private — acquisition helpers

    /// Evaluates an already-existing Lease.
    ///
    /// Returns the `RollbackLease` value object when we already hold it.
    /// Throws `.contention` when another live holder owns it.
    /// Throws `.conflict` when stale, so the caller retries.
    private func resolveContention(
        existing: coordination.v1.Lease,
        namespace: String,
        releaseName: String,
        holderIdentity: String,
        now: Date,
        nowString: String
    ) throws -> RollbackLease {
        let currentHolder = existing.spec?.holderIdentity ?? ""
        if currentHolder == holderIdentity {
            return makeValueObject(
                from: existing,
                namespace: namespace,
                releaseName: releaseName,
                holderIdentity: holderIdentity,
                nowString: nowString
            )
        }
        let valueObj = makeValueObject(
            from: existing,
            namespace: namespace,
            releaseName: releaseName,
            holderIdentity: holderIdentity,
            nowString: nowString
        )
        if valueObj.isStale(at: now) {
            throw RollbackLeaseError.conflict
        }
        throw RollbackLeaseError.contention(holderIdentity: currentHolder)
    }

    /// Creates a new Lease via HTTP POST.
    private func postNewLease(
        name: String,
        namespace: String,
        ns: NamespaceSelector,
        releaseName: String,
        holderIdentity: String,
        now: Date,
        nowString: String,
        client: KubernetesClient
    ) async throws -> RollbackLease {
        let resource = buildLeaseResource(
            name: name,
            namespace: namespace,
            holderIdentity: holderIdentity,
            acquireTime: now,
            renewTime: now
        )
        do {
            _ = try await client.coordinationV1.leases.create(inNamespace: ns, resource)
            return RollbackLease(
                namespace: namespace,
                releaseName: releaseName,
                holderIdentity: holderIdentity,
                acquireTime: nowString,
                renewTime: nowString
            )
        } catch let err as SwiftkubeClientError {
            if case .statusError(let status) = err, status.code == 409 {
                throw RollbackLeaseError.conflict
            }
            throw mapError(err)
        }
    }

    // MARK: - Private — Kubernetes object builders

    /// Constructs the `coordination.v1.Lease` payload for create/update.
    private func buildLeaseResource(
        name: String,
        namespace: String,
        holderIdentity: String,
        acquireTime: Date,
        renewTime: Date
    ) -> coordination.v1.Lease {
        let duration = Int32(RollbackLease.leaseDurationSeconds)
        return coordination.v1.Lease(
            metadata: meta.v1.ObjectMeta(
                labels: ["managed-by": "k8smanager", "context": "helm-rollback"],
                name: name,
                namespace: namespace
            ),
            spec: coordination.v1.LeaseSpec(
                acquireTime: acquireTime,
                holderIdentity: holderIdentity,
                leaseDurationSeconds: duration,
                renewTime: renewTime
            )
        )
    }

    /// Projects a live `coordination.v1.Lease` into a domain `RollbackLease`.
    private func makeValueObject(
        from lease: coordination.v1.Lease,
        namespace: String,
        releaseName: String,
        holderIdentity: String,
        nowString: String
    ) -> RollbackLease {
        RollbackLease(
            namespace: namespace,
            releaseName: releaseName,
            holderIdentity: holderIdentity,
            acquireTime: lease.spec?.acquireTime.map(formatISO8601) ?? nowString,
            renewTime: lease.spec?.renewTime.map(formatISO8601) ?? nowString
        )
    }

    // MARK: - Private — naming

    /// Returns `k8smanager-helm-rollback-<releaseName>` truncated to 63 chars.
    private func buildLeaseName(for releaseName: String) -> String {
        String("k8smanager-helm-rollback-\(releaseName)".prefix(63))
    }

    // MARK: - Private — client factory

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

    // MARK: - Private — error mapping

    private func mapError(_ err: SwiftkubeClientError) -> RollbackLeaseError {
        switch err {
        case .statusError(let status):
            let code = Int(status.code ?? 0)
            if code == 409 { return .conflict }
            return .unexpectedStatus(code: code, detail: status.message ?? "HTTP \(code)")
        case .clientError(let underlying):
            return .transportError(detail: underlying.localizedDescription)
        default:
            return .transportError(detail: String(describing: err))
        }
    }

    // MARK: - Private — date helpers

    private func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
