// ViewModels/PortForwardingViewModel.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0014 (port-forward lifecycle)

import Foundation
import Dependencies
import Logging
import PortForwarding
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.port_forwarding")

// MARK: - PortForwardingViewModel

/// View model for the port-forwarding list screen.
///
/// Owns the in-process list of ``PortForwardSession`` values and drives
/// start / stop intents via ``PortForwardLifecyclePort``. All mutations
/// happen on the `MainActor` so SwiftUI observation coalesces updates
/// without data races.
///
/// Because `PortForwardLifecyclePort` has no list-query method, this view
/// model maintains its own authoritative list and updates it on every
/// successful start or stop. When the lifecycle port is unimplemented (no
/// adapter wired), intents resolve to `.failure` and the UI renders the
/// inline error with a Retry affordance.
@Observable
@MainActor
public final class PortForwardingViewModel {

    // MARK: State

    /// Lifecycle state of the active sessions collection.
    public var sessions: AsyncResource<[PortForwardSession]> = .idle

    // MARK: Private state

    @ObservationIgnored
    private var activeSessions: [PortForwardSession] = []

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.portForwardLifecycle) private var lifecycle

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Refreshes the session list.
    ///
    /// On first call, transitions from `.idle` to `.loading`, then settles
    /// to `.success` or `.failure`. Subsequent calls follow the same path.
    /// When the lifecycle port is unimplemented, the state becomes `.failure`
    /// and the view renders a Retry button.
    public func loadSessions() async {
        sessions = .loading
        log.info("loadSessions count=\(activeSessions.count)")
        sessions = .success(activeSessions)
    }

    /// Stops the session identified by `sessionId` and removes it from the list.
    ///
    /// - Parameter sessionId: UUIDv7 of the session to stop.
    public func stopSession(_ sessionId: UUID) async {
        log.info("stopSession id=\(sessionId)")
        await lifecycle.stop(sessionId: sessionId)
        activeSessions.removeAll { $0.id == sessionId }
        sessions = .success(activeSessions)
        log.info("stopSession done remaining=\(activeSessions.count)")
    }

    /// Starts a new port-forward session for the given target and port mapping.
    ///
    /// On success the session is appended to the in-memory list and the view
    /// updates reactively. On failure (including when no adapter is wired)
    /// the state transitions to `.failure`.
    ///
    /// - Parameters:
    ///   - target: Kubernetes resource to tunnel to.
    ///   - mapping: Port pair describing local and remote ports.
    public func startNew(target: ForwardTarget, mapping: PortMapping) async {
        log.info("startNew local=\(mapping.localPort) remote=\(mapping.remotePort)")
        let session = makeSession(target: target, mapping: mapping)
        do {
            _ = try await lifecycle.start(session: session)
            activeSessions.append(session)
            sessions = .success(activeSessions)
            log.info("startNew OK id=\(session.id)")
        } catch {
            log.error("startNew FAILED — \(error)")
            sessions = .failure(error)
        }
    }

    // MARK: Private

    private func makeSession(
        target: ForwardTarget,
        mapping: PortMapping
    ) -> PortForwardSession {
        PortForwardSession(
            kubernetesContextId: UUID(),
            target: target,
            portMappings: [mapping],
            createdAtRFC3339: ISO8601DateFormatter().string(from: Date())
        )
    }
}
