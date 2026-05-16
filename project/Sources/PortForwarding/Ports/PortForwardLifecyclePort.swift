// Ports/PortForwardLifecyclePort.swift — port_forwarding bounded context
// DDD role: Port (primary — inbound, session start/stop driven by the application)
// ADR ref: ADR-0014 (cooperative cancellation, 200 ms shutdown, 500 ms app-quit deadline)
// Narrative ref: docs/arch/contexts/port_forwarding/domain/narrative.md §Tactical roles

import Foundation

// MARK: - PortForwardLifecyclePort

/// Primary port that the application layer uses to start and stop port-forward sessions.
///
/// Declared in the domain core; implemented by `PortForwardManagerActor` in the
/// infrastructure layer (or a test double for unit tests). The application layer
/// (e.g., `AppShell`) never interacts with `URLSessionWebSocketTask` directly.
///
/// Each `start(session:)` call creates and returns an `AsyncStream` of
/// ``PortForwardEvent`` values for the lifetime of that session. The stream
/// finishes when the session reaches `closed` or `error`.
///
/// Cancellation contract (ADR-0014):
/// - `stop(sessionId:)` initiates cooperative shutdown. The implementation must
///   close all local TCP listeners and complete the WebSocket close handshake
///   within **200 ms**.
/// - On application quit, the caller must call `stopAll()` and await its return
///   within a **500 ms** total deadline before process exit.
public protocol PortForwardLifecyclePort: Sendable {
    /// Starts a new port-forward session and returns the event stream for that session.
    ///
    /// The returned `AsyncStream` emits ``PortForwardEvent`` values in the order they
    /// are produced by the session actor. The stream finishes (yielding no more values)
    /// once the session reaches `closed` or `error`.
    ///
    /// - Parameter session: The ``PortForwardSession`` aggregate that describes the
    ///   target, port mappings, and initial lifecycle state. The `status` field must
    ///   be `opening` at call time.
    /// - Returns: An `AsyncStream` of ``PortForwardEvent`` values for this session.
    /// - Throws: ``PortForwardLifecycleError`` if the session cannot be started.
    func start(session: PortForwardSession) async throws -> AsyncStream<PortForwardEvent>

    /// Stops the port-forward session identified by `sessionId`.
    ///
    /// Initiates cooperative shutdown: closes all bound TCP listeners and sends a
    /// WebSocket Close frame to the Kubernetes API server. The implementation must
    /// complete the close handshake within 200 ms; after that deadline any remaining
    /// resources are forcibly released.
    ///
    /// Calling `stop` on a session that is already `closed` or `error` is a no-op.
    ///
    /// - Parameter sessionId: UUIDv7 of the session to stop.
    func stop(sessionId: UUID) async

    /// Stops all active sessions, waiting for each to complete cooperative shutdown.
    ///
    /// Called by `AppDelegate.applicationWillTerminate` with a total deadline of
    /// 500 ms (ADR-0014 §Security and operational constraints). Implementations must
    /// respect this deadline and return before process exit.
    func stopAll() async
}

// MARK: - PortForwardLifecycleError

/// Errors raised by ``PortForwardLifecyclePort`` implementations.
public enum PortForwardLifecycleError: Error, Sendable {
    /// Port has not been registered in this process.
    case unimplemented
    /// A session with the given `sessionId` is already active.
    case sessionAlreadyActive(sessionId: UUID)
    /// The provided ``PortForwardSession`` is in a terminal state and cannot be started.
    case sessionIsTerminal(sessionId: UUID)
    /// The provided `portMappings` list is empty; at least one mapping is required.
    case emptyPortMappings
}

// MARK: - UnimplementedPortForwardLifecyclePort

/// Crash-fast sentinel used before an actor implementation is registered.
public struct UnimplementedPortForwardLifecyclePort: PortForwardLifecyclePort {
    public init() {}

    public func start(session: PortForwardSession) async throws -> AsyncStream<PortForwardEvent> {
        throw PortForwardLifecycleError.unimplemented
    }

    public func stop(sessionId: UUID) async {}

    public func stopAll() async {}
}
