// Actors/NamespaceFilterActor.swift — app_shell bounded context
// DDD role: AggregateRoot — global namespace filter state per cluster
// ADR ref: ADR-0050 (resource navigation), ADR-0051 (cluster-scoped UI state)
//
// Concurrency contract:
//   - All mutations isolated to this actor.
//   - Per-subscriber filtering: continuations are keyed by the cluster they
//     observe so a namespace change in cluster A never wakes subscribers
//     watching cluster B.

import Dependencies
import Foundation
import SharedKernel

// MARK: - NamespaceFilterSnapshot

/// Sendable snapshot emitted by ``NamespaceFilterActor/stateStream(for:)``.
///
/// `namespace == nil` means "all namespaces" — the default for newly observed
/// clusters and the natural starting state every workload list view should
/// render on first load.
public struct NamespaceFilterSnapshot: Sendable, Equatable {
    public let clusterId: ClusterId
    public let namespace: String?

    public init(clusterId: ClusterId, namespace: String?) {
        self.clusterId = clusterId
        self.namespace = namespace
    }
}

// MARK: - NamespaceFilterActor

/// Process-wide actor that owns the selected namespace per cluster.
///
/// Workload list view models (Pods, Deployments, DaemonSets…) subscribe to
/// ``stateStream(for:)`` and re-fetch whenever the snapshot for their cluster
/// changes. The toolbar `GlobalNamespacePicker` drives the actor via
/// ``setNamespace(_:for:)``, so a single dropdown filters the entire app.
public actor NamespaceFilterActor {

    // MARK: State

    /// Currently selected namespace per cluster. Missing key = no filter applied.
    private var selected: [ClusterId: String] = [:]

    /// Live continuations keyed by the cluster they observe so broadcasts can
    /// skip subscribers from unrelated clusters.
    private var subscribers: [UUID: (clusterId: ClusterId, cont: AsyncStream<NamespaceFilterSnapshot>.Continuation)] = [:]

    public init() {}

    // MARK: Queries

    /// Returns the namespace currently applied to `clusterId`, or `nil` for "all".
    public func current(for clusterId: ClusterId) -> String? {
        selected[clusterId]
    }

    // MARK: Mutations

    /// Sets the namespace for `clusterId` and broadcasts to subscribers of that cluster.
    ///
    /// Pass `nil` to switch to "all namespaces". No-op when the value is unchanged.
    public func setNamespace(_ namespace: String?, for clusterId: ClusterId) {
        if selected[clusterId] == namespace { return }
        if let namespace {
            selected[clusterId] = namespace
        } else {
            selected.removeValue(forKey: clusterId)
        }
        let snap = NamespaceFilterSnapshot(clusterId: clusterId, namespace: namespace)
        for (key, sub) in subscribers where sub.clusterId == clusterId {
            sub.cont.yield(snap)
            _ = key
        }
    }

    // MARK: Stream

    /// AsyncStream emitting the current namespace for `clusterId` on every change.
    ///
    /// Yields the current state once immediately so callers can read initial
    /// value via `for await` without a separate `current(for:)` round-trip.
    public nonisolated func stateStream(for clusterId: ClusterId) -> AsyncStream<NamespaceFilterSnapshot> {
        let key = UUID()
        return AsyncStream { continuation in
            Task { await self.register(key: key, clusterId: clusterId, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unregister(key: key) }
            }
        }
    }

    // MARK: Internal

    private func register(
        key: UUID,
        clusterId: ClusterId,
        continuation: AsyncStream<NamespaceFilterSnapshot>.Continuation
    ) {
        let initial = NamespaceFilterSnapshot(clusterId: clusterId, namespace: selected[clusterId])
        continuation.yield(initial)
        subscribers[key] = (clusterId, continuation)
    }

    private func unregister(key: UUID) {
        subscribers.removeValue(forKey: key)
    }
}

// MARK: - DependencyValues integration

/// Public dependency key resolved by every workload list view model and the
/// global toolbar picker.
public enum NamespaceFilterDependencyKey: DependencyKey {
    public static let liveValue: NamespaceFilterActor = NamespaceFilterActor()
    public static let testValue: NamespaceFilterActor = NamespaceFilterActor()
}

extension DependencyValues {
    /// Process-wide namespace filter actor — see ``NamespaceFilterActor``.
    public var namespaceFilter: NamespaceFilterActor {
        get { self[NamespaceFilterDependencyKey.self] }
        set { self[NamespaceFilterDependencyKey.self] = newValue }
    }
}
