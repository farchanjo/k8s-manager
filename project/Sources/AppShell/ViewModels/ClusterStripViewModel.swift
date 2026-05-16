// ViewModels/ClusterStripViewModel.swift — app_shell bounded context
// DDD role: ViewModel (presentation projection of ClusterStripActor)
// ADR ref: ADR-0051 (cluster strip), ADR-0034 (state-driven realtime UI)

import Foundation
import SharedKernel

// MARK: - ClusterStripViewModel

/// `@MainActor` observable view model for the vertical cluster strip.
///
/// Subscribes to ``ClusterStripActor/stateStream()`` and projects the actor's
/// ``ClusterStripSnapshot`` into properties that SwiftUI observes directly.
/// Mutation intents delegate back to the actor.
@Observable
@MainActor
public final class ClusterStripViewModel {

    // MARK: Published state

    /// Ordered list of pinned clusters consumed by `ClusterStripView`.
    public var pins: [ClusterStripPin] = []

    /// Currently selected cluster identifier.
    public var activeClusterId: ClusterId?

    /// Controls the cluster picker sheet presentation.
    public var showingClusterPicker: Bool = false

    // MARK: Dependencies

    private let actor: ClusterStripActor

    // MARK: Init

    public init(actor: ClusterStripActor = ClusterStripActor()) {
        self.actor = actor
    }

    // MARK: Lifecycle

    /// Starts consuming the actor state stream.
    ///
    /// Call from `.task` on the owning view so the subscription is tied to
    /// view lifetime and automatically cancelled on disappear.
    public func start() async {
        for await snapshot in await actor.stateStream() {
            pins = snapshot.pins
            activeClusterId = snapshot.activeClusterId
        }
    }

    // MARK: Intents

    /// Sets `clusterId` as the active cluster in the strip.
    public func activate(_ clusterId: ClusterId) async {
        await actor.setActive(clusterId)
    }

    /// Removes a cluster from the strip.
    public func unpin(_ clusterId: ClusterId) async {
        await actor.unpin(clusterId)
    }

    /// Pins a new cluster, typically called from ``ClusterPickerSheet``.
    public func pin(_ clusterId: ClusterId, displayName: String) async throws {
        try await actor.pin(clusterId: clusterId, displayName: displayName)
    }

    /// Reorders pins to match the given cluster-id sequence.
    public func reorder(_ newOrder: [ClusterId]) async {
        await actor.reorder(newOrder)
    }
}
