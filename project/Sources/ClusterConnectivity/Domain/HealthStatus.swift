// Domain/HealthStatus.swift — cluster_connectivity bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/cluster_connectivity/schemas/health_status.cue

import Foundation
import SharedKernel

// MARK: - HealthState

/// Discriminated result of a single cluster health probe.
///
/// Mirrors `#HealthState` from `health_status.cue`.
public enum HealthState: String, Hashable, Sendable, Codable, CaseIterable {
    /// Probe completed and the API server returned 200 on `/readyz` or
    /// `/healthz`.
    case reachable

    /// Probe completed but the health endpoint reported non-200 or partial
    /// readiness.
    case degraded

    /// Network or TLS error before a response was received.
    case unreachable

    /// HTTP 401 — authentication was rejected.
    case unauthorized

    /// HTTP 403 — authentication succeeded but the identity lacks probe
    /// permission.
    case forbidden

    /// Initial state before any probe has run.
    case unknown
}

// MARK: - HealthStatus

/// Immutable result of a single cluster health probe.
///
/// Mirrors `#HealthStatus` from `health_status.cue`. Produced by
/// `ClusterHealthProbe`. Consumers should treat it as read-only. The `detail`
/// field MUST NOT contain credential material, kubeconfig paths, or token
/// fingerprints.
public struct HealthStatus: Hashable, Sendable, Codable {
    /// The cluster this probe targeted.
    public let clusterId: ClusterId

    /// RFC 3339 timestamp when the probe ran.
    public let probedAt: String

    /// Outcome of the probe.
    public let state: HealthState

    /// Wall-clock latency of the probe round-trip in milliseconds. Absent when
    /// the probe failed before establishing a connection.
    public let latencyMillis: Int?

    /// Human-readable explanation for the operator. Must not contain
    /// credential material.
    public let detail: String?

    public init(
        clusterId: ClusterId,
        probedAt: String,
        state: HealthState,
        latencyMillis: Int? = nil,
        detail: String? = nil
    ) {
        self.clusterId = clusterId
        self.probedAt = probedAt
        self.state = state
        self.latencyMillis = latencyMillis
        self.detail = detail
    }
}
