// Ports/WatchPort.swift — cluster_connectivity bounded context
// DDD role: Port (outbound — streaming domain events from a cluster session)
// ADR ref: ADR-0025 (per-cluster isolation)
// Narrative ref: domain/narrative.md §Per-cluster session isolation

import Foundation
import SharedKernel

// MARK: - WatchPort

/// Streams `ClusterSessionEvent` values published by a `ClusterSessionActor`.
///
/// Declared in the domain core; implemented by adapters that wire the actor's
/// `AsyncThrowingStream` to callers. The domain core never imports any
/// infrastructure library.
public protocol WatchPort: Sendable {
    /// Returns a stream of `ClusterSessionEvent` values for the given cluster.
    ///
    /// The stream terminates normally after a `sessionTerminated` event.
    /// Consumers should `for try await` over the stream and handle
    /// `ClusterSessionEvent.sessionTerminated` as the completion signal.
    ///
    /// - Parameter clusterId: The shared-kernel identifier of the cluster whose
    ///   session events are being watched.
    /// - Returns: An `AsyncThrowingStream` that emits `ClusterSessionEvent`
    ///   values until the session is terminated or an error occurs.
    func watchClusterSessionEvents(
        clusterId: ClusterId
    ) -> AsyncThrowingStream<ClusterSessionEvent, Error>
}

// MARK: - WatchPortError

/// Errors raised by `WatchPort` implementations.
public enum WatchPortError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// No session exists for the requested cluster.
    case noSessionForCluster(ClusterId)
}

// MARK: - UnimplementedWatchPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedWatchPort: WatchPort {
    public init() {}

    public func watchClusterSessionEvents(
        clusterId: ClusterId
    ) -> AsyncThrowingStream<ClusterSessionEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: WatchPortError.unimplemented)
        }
    }
}
