// Domain/ClusterSessionEvent.swift — cluster_connectivity bounded context
// DDD role: DomainEvent / ValueObject
// CUE source: docs/arch/contexts/cluster_connectivity/schemas/cluster_session_event.cue

import Foundation
import SharedKernel

// MARK: - DegradationReason

/// Coarse-grain reason a session entered the degraded state.
///
/// Mirrors the `reason` disjunction on `#SessionDegraded`.
public enum DegradationReason: String, Hashable, Sendable, Codable {
    case noCredentials = "no-credentials"
    case execPluginFailed = "exec-plugin-failed"
    case certificateExpired = "certificate-expired"
}

// MARK: - DisconnectionReason

/// Coarse-grain reason a session lost connectivity.
///
/// Mirrors the `reason` disjunction on `#SessionDisconnected`.
public enum DisconnectionReason: String, Hashable, Sendable, Codable {
    case network
    case serverError = "server-error"
    case operatorPause = "operator-pause"
}

// MARK: - TerminationReason

/// Reason a session was fully torn down.
///
/// Mirrors the `reason` disjunction on `#SessionTerminated`.
public enum TerminationReason: String, Hashable, Sendable, Codable {
    case operatorRequested = "operator-requested"
    case idleTimeout = "idle-timeout"
    case sessionCapExceeded = "session-cap-exceeded"
    case applicationExit = "application-exit"
}

// MARK: - ClusterSessionEvent

/// Discriminated union of all domain events a `ClusterSessionActor` may
/// publish to observers via `AsyncThrowingStream`.
///
/// Mirrors `#ClusterSessionEvent` from `cluster_session_event.cue`. All
/// variants are immutable value objects.
public enum ClusterSessionEvent: Hashable, Sendable, Codable {
    /// The session is now fully open and connected to the API server.
    case sessionOpened(SessionOpened)

    /// The session is technically alive but a required capability is
    /// unavailable (e.g., expired exec-plugin credential).
    case sessionDegraded(SessionDegraded)

    /// The session has lost connectivity and is attempting to reconnect.
    case sessionDisconnected(SessionDisconnected)

    /// The session has completed full teardown. No further events follow.
    case sessionTerminated(SessionTerminated)

    /// Periodic heartbeat carrying a fresh connection-pool snapshot.
    case poolStatsSnapshot(PoolStatsSnapshot)

    // MARK: - SessionOpened

    /// Published when `ClusterSessionActor` transitions to `connected`.
    public struct SessionOpened: Hashable, Sendable, Codable {
        public let sessionId: UUID
        public let clusterId: ClusterId
        public let kubernetesContextId: UUID
        public let occurredAt: String

        public init(
            sessionId: UUID,
            clusterId: ClusterId,
            kubernetesContextId: UUID,
            occurredAt: String
        ) {
            self.sessionId = sessionId
            self.clusterId = clusterId
            self.kubernetesContextId = kubernetesContextId
            self.occurredAt = occurredAt
        }
    }

    // MARK: - SessionDegraded

    /// Published when the session is alive but a required capability is
    /// unavailable.
    public struct SessionDegraded: Hashable, Sendable, Codable {
        public let sessionId: UUID
        public let clusterId: ClusterId
        public let reason: DegradationReason
        /// Human-readable description of the cause. Must not contain
        /// credential material.
        public let detail: String
        public let occurredAt: String

        public init(
            sessionId: UUID,
            clusterId: ClusterId,
            reason: DegradationReason,
            detail: String,
            occurredAt: String
        ) {
            self.sessionId = sessionId
            self.clusterId = clusterId
            self.reason = reason
            self.detail = detail
            self.occurredAt = occurredAt
        }
    }

    // MARK: - SessionDisconnected

    /// Published when the session has lost connectivity to the API server.
    public struct SessionDisconnected: Hashable, Sendable, Codable {
        public let sessionId: UUID
        public let clusterId: ClusterId
        public let reason: DisconnectionReason
        /// Human-readable description safe for UI display. Must not contain
        /// credential material.
        public let detail: String
        public let occurredAt: String

        public init(
            sessionId: UUID,
            clusterId: ClusterId,
            reason: DisconnectionReason,
            detail: String,
            occurredAt: String
        ) {
            self.sessionId = sessionId
            self.clusterId = clusterId
            self.reason = reason
            self.detail = detail
            self.occurredAt = occurredAt
        }
    }

    // MARK: - SessionTerminated

    /// Terminal event: published after full `ClusterSessionActor` teardown.
    public struct SessionTerminated: Hashable, Sendable, Codable {
        public let sessionId: UUID
        public let clusterId: ClusterId
        public let reason: TerminationReason
        public let occurredAt: String

        public init(
            sessionId: UUID,
            clusterId: ClusterId,
            reason: TerminationReason,
            occurredAt: String
        ) {
            self.sessionId = sessionId
            self.clusterId = clusterId
            self.reason = reason
            self.occurredAt = occurredAt
        }
    }

    // MARK: - PoolStatsSnapshot

    /// Periodic heartbeat with a fresh connection-pool snapshot.
    public struct PoolStatsSnapshot: Hashable, Sendable, Codable {
        public let sessionId: UUID
        public let clusterId: ClusterId
        public let stats: PoolStats
        public let occurredAt: String

        public init(
            sessionId: UUID,
            clusterId: ClusterId,
            stats: PoolStats,
            occurredAt: String
        ) {
            self.sessionId = sessionId
            self.clusterId = clusterId
            self.stats = stats
            self.occurredAt = occurredAt
        }
    }
}
