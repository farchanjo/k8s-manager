// Domain/RollbackLease.swift — helm_management bounded context
// DDD role: ValueObject (Lease state for mutual exclusion)
// ADR ref: ADR-0046 (Helm rollback Lease-based mutual exclusion)

import Foundation

// MARK: - RollbackLease

/// In-memory representation of a `coordination.k8s.io/v1/Lease` that guards
/// rollback mutual exclusion for a single Helm release.
///
/// The actual Lease object lives in the Kubernetes API server under:
/// - Namespace: same namespace as the Helm release Secret.
/// - Name: `k8smanager-helm-rollback-<release-name>` (kebab-case, max 63 chars).
///
/// Per ADR-0046, only one holder may perform a rollback at a time.
/// The holder renews the lease every 20 seconds while rollback is in progress.
/// The lease auto-expires after `leaseDurationSeconds` (60 s) when the holding
/// process crashes.
public struct RollbackLease: Hashable, Sendable, Codable {
    /// Kubernetes namespace of the Helm release. The Lease object is created
    /// in this same namespace.
    public let namespace: String

    /// Name of the Helm release being rolled back.
    public let releaseName: String

    /// `spec.holderIdentity` written to the Lease.
    /// Format: `k8smanager-<instanceId>-<operatorEmail>`.
    public let holderIdentity: String

    /// `spec.acquireTime` — RFC3339 timestamp set when the lease was acquired.
    public let acquireTime: String

    /// `spec.renewTime` — RFC3339 timestamp, refreshed every 20 s while
    /// rollback is in progress.
    public let renewTime: String

    /// `spec.leaseDurationSeconds` per ADR-0046 decision: 60 seconds.
    public static let leaseDurationSeconds: Int = 60

    /// Renewal interval per ADR-0046: 20 seconds.
    public static let renewIntervalSeconds: Int = 20

    /// Computed Kubernetes object name for the Lease.
    /// Format: `k8smanager-helm-rollback-<release-name>`, truncated to 63
    /// characters per RFC 1123.
    public var leaseName: String {
        let raw = "k8smanager-helm-rollback-\(releaseName)"
        return String(raw.prefix(63))
    }

    /// Returns `true` when the lease is considered stale.
    ///
    /// A lease is stale when `renewTime + leaseDurationSeconds < referenceDate`.
    /// Stale leases may be overwritten by a competing instance per ADR-0046 §Acquisition.
    ///
    /// - Parameter referenceDate: The current time to compare against. Accepts
    ///   an injectable value for deterministic tests.
    public func isStale(at referenceDate: Date) -> Bool {
        let formatter = ISO8601DateFormatter()
        guard let renew = formatter.date(from: renewTime) else { return true }
        return renew.addingTimeInterval(Double(RollbackLease.leaseDurationSeconds)) < referenceDate
    }

    public init(
        namespace: String,
        releaseName: String,
        holderIdentity: String,
        acquireTime: String,
        renewTime: String
    ) {
        self.namespace = namespace
        self.releaseName = releaseName
        self.holderIdentity = holderIdentity
        self.acquireTime = acquireTime
        self.renewTime = renewTime
    }
}
