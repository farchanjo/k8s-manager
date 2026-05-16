// Actors/PortForwardManagerActor.swift — port_forwarding bounded context
// DDD role: DomainService (actor, one instance per session)
// ADR ref: ADR-0014 (lifecycle state machine, cooperative cancellation, 200 ms deadline)
// Narrative ref: docs/arch/contexts/port_forwarding/domain/narrative.md §PortForwardManagerActor

import Foundation

// MARK: - PortForwardManagerActor

/// Domain-service actor that owns the complete lifecycle of one port-forward session.
///
/// One actor instance is created per ``PortForwardSession`` aggregate. Actors are never
/// pooled or reused across sessions (ADR-0014 §PortForwardManagerActor).
///
/// Responsibilities:
/// - Drives the session lifecycle state machine (opening → running → closing → closed,
///   with `error` reachable from `opening` and `running`).
/// - Opens the `portforward.k8s.io` WebSocket channel via ``PortForwardChannelPort``.
/// - Emits ``PortForwardEvent`` values to all subscribers via `AsyncStream`.
/// - Implements cooperative cancellation: all resources must be released within 200 ms
///   of `stop()` (ADR-0014 §WebSocket close handshake).
///
/// The actor is not `Sendable`-conforming by name — actor types are implicitly `Sendable`.
public actor PortForwardManagerActor {
    // MARK: - State

    /// Current snapshot of the session aggregate. Mutated exclusively by this actor.
    private var session: PortForwardSession

    /// WebSocket channel to the Kubernetes portforward subresource.
    private let channel: any PortForwardChannelPort

    /// Continuation used to yield events to subscribers. Finished when the session
    /// reaches `closed` or `error`.
    private let eventContinuation: AsyncStream<PortForwardEvent>.Continuation

    /// The `AsyncStream` vended to callers of ``events()``.
    private let eventStream: AsyncStream<PortForwardEvent>

    // MARK: - Init

    /// Creates a new actor for the given session, backed by `channel`.
    ///
    /// - Parameters:
    ///   - session: The ``PortForwardSession`` aggregate in `opening` state.
    ///   - channel: The ``PortForwardChannelPort`` that will carry WebSocket frames.
    public init(session: PortForwardSession, channel: any PortForwardChannelPort) {
        precondition(session.status == .opening, "Actor must be initialized with an .opening session")
        self.session = session
        self.channel = channel
        var continuation: AsyncStream<PortForwardEvent>.Continuation!
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    // MARK: - Public API

    /// Starts the port-forward session: opens the channel, advances the session to
    /// `.running`, and emits a ``PortForwardEvent/sessionOpened(_:)`` event.
    ///
    /// - Throws: ``PortForwardChannelError`` on WebSocket upgrade failure; the session
    ///   transitions to `.error` and a ``PortForwardEvent/sessionFailed(_:)`` event is
    ///   emitted before rethrowing.
    public func start() async throws {
        let ports = session.portMappings.map(\.remotePort)
        let namespace = session.target.namespace
        let podName = resolvedPodName()

        do {
            try await channel.open(namespace: namespace, podName: podName, ports: ports)
        } catch {
            await transitionToError(errorCode: "websocket_upgrade_failed", detail: error.localizedDescription)
            throw error
        }

        let now = ISO8601DateFormatter().string(from: Date())
        session = session.opened(at: now)
        emit(.sessionOpened(.init(sessionId: session.id, occurredAtRFC3339: now)))
    }

    /// Stops the session cooperatively: transitions to `.closing`, closes the channel,
    /// then transitions to `.closed` and emits ``PortForwardEvent/sessionClosed(_:)``.
    ///
    /// Calling `stop()` on a session that is already in a terminal state is a no-op.
    /// The channel close handshake must complete within 200 ms (ADR-0014).
    public func stop() async {
        guard session.status == .running else { return }
        session = session.beginClosing()

        await channel.close()

        let now = ISO8601DateFormatter().string(from: Date())
        session = session.closed(at: now)
        emit(.sessionClosed(.init(sessionId: session.id, occurredAtRFC3339: now)))
        eventContinuation.finish()
    }

    /// Returns the `AsyncStream` of ``PortForwardEvent`` values for this session.
    ///
    /// The stream finishes when the session reaches `closed` or `error`. Multiple
    /// callers receive independent iterators over the same underlying stream.
    public func events() -> AsyncStream<PortForwardEvent> {
        eventStream
    }

    // MARK: - Inbound frame dispatch

    /// Handles an inbound data frame from the WebSocket channel.
    ///
    /// Dispatches the frame payload to the appropriate port mapping identified by
    /// `frame.portIndex`. Emits a ``PortForwardEvent/bytesTransferred(_:)`` snapshot
    /// if the session is `running`.
    ///
    /// - Parameter frame: A decoded data frame from the `portforward.k8s.io` protocol.
    func handleChannelData(_ frame: PortForwardFrame) {
        guard session.status == .running, frame.streamType == .data else { return }
        guard !frame.payload.isEmpty else { return } // EOF sentinel — handled at caller

        let now = ISO8601DateFormatter().string(from: Date())
        let bytesIn = frame.payload.count
        emit(.bytesTransferred(.init(
            sessionId: session.id,
            occurredAtRFC3339: now,
            bytesIn: bytesIn,
            bytesOut: 0
        )))
    }

    /// Handles an inbound error frame from the WebSocket channel.
    ///
    /// Extracts the error message from `frame.payload` and transitions the session to
    /// `.error`, emitting a ``PortForwardEvent/sessionFailed(_:)`` event.
    ///
    /// - Parameter frame: A decoded error frame from the `portforward.k8s.io` protocol.
    func handleChannelError(_ frame: PortForwardFrame) {
        guard session.status == .running || session.status == .opening else { return }
        let detail = String(bytes: frame.payload, encoding: .utf8) ?? "unknown error from port \(frame.portIndex)"
        Task { await transitionToError(errorCode: "channel_error_frame", detail: detail) }
    }

    // MARK: - Private helpers

    private func resolvedPodName() -> String {
        switch session.target {
        case .pod(let t): return t.podName
        case .service(let t): return t.resolvedPodName ?? t.serviceName
        }
    }

    private func transitionToError(errorCode: String, detail: String) async {
        guard session.status == .opening || session.status == .running else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        session = session.failed(at: now)
        emit(.sessionFailed(.init(
            sessionId: session.id,
            occurredAtRFC3339: now,
            errorCode: errorCode,
            detail: detail
        )))
        eventContinuation.finish()
    }

    private func emit(_ event: PortForwardEvent) {
        eventContinuation.yield(event)
    }
}
