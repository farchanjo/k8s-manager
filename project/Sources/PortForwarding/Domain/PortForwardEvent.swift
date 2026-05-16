// Domain/PortForwardEvent.swift — port_forwarding bounded context
// DDD role: DomainEvent / ValueObject
// CUE source: docs/arch/contexts/port_forwarding/schemas/port_forward_event.cue
// ADR ref: ADR-0014 (lifecycle transitions and event invariants)

import Foundation

// MARK: - PortForwardEvent

/// Discriminated union of all domain events emitted by `PortForwardManagerActor`
/// during the lifecycle of a ``PortForwardSession``.
///
/// Events are immutable value objects published via `AsyncStream` to the UI and
/// to the `ActivePortForwardsReadModel` projection.
///
/// Invariants:
/// - Every variant carries a `sessionId` that references the owning session.
/// - ``SessionFailed`` must never contain credential material (tokens, certificates,
///   kubeconfig secrets) in `errorCode` or `detail`.
/// - ``BytesTransferred`` is emitted at most once every 5 seconds per session
///   (aggregated counter, never per-frame payload).
///
/// Mirrors `#PortForwardEvent` from `port_forward_event.cue`.
public enum PortForwardEvent: Hashable, Sendable, Codable {
    /// WebSocket upgrade handshake succeeded; session is now `running`.
    case sessionOpened(SessionOpened)
    /// Session transitioned to `error` from `opening` or `running`.
    case sessionFailed(SessionFailed)
    /// A local TCP server socket was successfully bound for one port mapping.
    case listenerBound(ListenerBound)
    /// A local TCP server socket was closed during shutdown or after failure.
    case listenerClosed(ListenerClosed)
    /// A local TCP client connected to one of the bound listeners.
    case connectionAccepted(ConnectionAccepted)
    /// Aggregated byte-count snapshot (at most once per 5 s; no payload content).
    case bytesTransferred(BytesTransferred)
    /// Session transitioned to `closed` after cooperative shutdown.
    case sessionClosed(SessionClosed)

    // MARK: - SessionOpened

    /// Published when the WebSocket upgrade completes and the session is `running`.
    ///
    /// Mirrors `#SessionOpened` from `port_forward_event.cue`.
    public struct SessionOpened: Hashable, Sendable, Codable {
        /// UUIDv7 of the owning ``PortForwardSession``.
        public let sessionId: UUID
        /// RFC 3339 timestamp when the event was produced.
        public let occurredAtRFC3339: String

        public init(sessionId: UUID, occurredAtRFC3339: String) {
            self.sessionId = sessionId
            self.occurredAtRFC3339 = occurredAtRFC3339
        }
    }

    // MARK: - SessionFailed

    /// Published when the session transitions to `error`.
    ///
    /// `detail` must never contain credential material.
    ///
    /// Mirrors `#SessionFailed` from `port_forward_event.cue`.
    public struct SessionFailed: Hashable, Sendable, Codable {
        /// UUIDv7 of the owning ``PortForwardSession``.
        public let sessionId: UUID
        /// RFC 3339 timestamp when the event was produced.
        public let occurredAtRFC3339: String
        /// Machine-readable failure category, e.g. `"websocket_upgrade_rejected"`,
        /// `"pod_not_found"`, `"local_bind_failed"`.
        public let errorCode: String
        /// Human-readable explanation. Must not include credential material.
        public let detail: String

        public init(
            sessionId: UUID,
            occurredAtRFC3339: String,
            errorCode: String,
            detail: String
        ) {
            self.sessionId = sessionId
            self.occurredAtRFC3339 = occurredAtRFC3339
            self.errorCode = errorCode
            self.detail = detail
        }
    }

    // MARK: - ListenerBound

    /// Published once per ``PortMapping`` when the local TCP server socket is bound.
    ///
    /// `effectiveLocalPort` may differ from the requested port when the operator
    /// specified 0 for dynamic assignment.
    ///
    /// Mirrors `#ListenerBound` from `port_forward_event.cue`.
    public struct ListenerBound: Hashable, Sendable, Codable {
        /// UUIDv7 of the owning ``PortForwardSession``.
        public let sessionId: UUID
        /// RFC 3339 timestamp when the event was produced.
        public let occurredAtRFC3339: String
        /// 0-based index of this mapping in the session's `portMappings` list,
        /// matching the `portIndex` byte in the wire protocol frame header.
        public let portIndex: Int
        /// Kernel-assigned port after `bind(2)` / `listen(2)`. Equals the requested
        /// `localPort` unless dynamic assignment (port 0) was requested.
        public let effectiveLocalPort: Int
        /// Local IP address the listener is bound to.
        public let bindAddress: String
        /// `true` when `bindAddress` is not `"127.0.0.1"`, indicating the tunnel is
        /// accessible beyond the loopback interface.
        public let isNetworkExposed: Bool

        public init(
            sessionId: UUID,
            occurredAtRFC3339: String,
            portIndex: Int,
            effectiveLocalPort: Int,
            bindAddress: String,
            isNetworkExposed: Bool
        ) {
            self.sessionId = sessionId
            self.occurredAtRFC3339 = occurredAtRFC3339
            self.portIndex = portIndex
            self.effectiveLocalPort = effectiveLocalPort
            self.bindAddress = bindAddress
            self.isNetworkExposed = isNetworkExposed
        }
    }

    // MARK: - ListenerClosed

    /// Published once per ``PortMapping`` when the local TCP server socket is closed.
    ///
    /// Mirrors `#ListenerClosed` from `port_forward_event.cue`.
    public struct ListenerClosed: Hashable, Sendable, Codable {
        /// UUIDv7 of the owning ``PortForwardSession``.
        public let sessionId: UUID
        /// RFC 3339 timestamp when the event was produced.
        public let occurredAtRFC3339: String
        /// 0-based index of the mapping whose listener was closed.
        public let portIndex: Int

        public init(sessionId: UUID, occurredAtRFC3339: String, portIndex: Int) {
            self.sessionId = sessionId
            self.occurredAtRFC3339 = occurredAtRFC3339
            self.portIndex = portIndex
        }
    }

    // MARK: - ConnectionAccepted

    /// Published each time a local TCP client connects to one of the bound listeners.
    ///
    /// No payload data is included; only the client address and ephemeral port.
    ///
    /// Mirrors `#ConnectionAccepted` from `port_forward_event.cue`.
    public struct ConnectionAccepted: Hashable, Sendable, Codable {
        /// UUIDv7 of the owning ``PortForwardSession``.
        public let sessionId: UUID
        /// RFC 3339 timestamp when the event was produced.
        public let occurredAtRFC3339: String
        /// 0-based index of the mapping the client connected to.
        public let portIndex: Int
        /// IP address of the local TCP client.
        public let clientAddress: String
        /// Ephemeral source port assigned to the TCP client connection by the kernel.
        public let clientPort: Int

        public init(
            sessionId: UUID,
            occurredAtRFC3339: String,
            portIndex: Int,
            clientAddress: String,
            clientPort: Int
        ) {
            self.sessionId = sessionId
            self.occurredAtRFC3339 = occurredAtRFC3339
            self.portIndex = portIndex
            self.clientAddress = clientAddress
            self.clientPort = clientPort
        }
    }

    // MARK: - BytesTransferred

    /// Aggregated byte-count snapshot emitted at most once per 5 seconds per session.
    ///
    /// Carries aggregate counts only; no tunnelled payload content is ever included.
    ///
    /// Mirrors `#BytesTransferred` from `port_forward_event.cue`.
    public struct BytesTransferred: Hashable, Sendable, Codable {
        /// UUIDv7 of the owning ``PortForwardSession``.
        public let sessionId: UUID
        /// RFC 3339 timestamp when the event was produced.
        public let occurredAtRFC3339: String
        /// Cumulative bytes received from the Kubernetes API server (remote → local)
        /// since the last emission.
        public let bytesIn: Int
        /// Cumulative bytes sent to the Kubernetes API server (local → remote)
        /// since the last emission.
        public let bytesOut: Int

        public init(
            sessionId: UUID,
            occurredAtRFC3339: String,
            bytesIn: Int,
            bytesOut: Int
        ) {
            self.sessionId = sessionId
            self.occurredAtRFC3339 = occurredAtRFC3339
            self.bytesIn = bytesIn
            self.bytesOut = bytesOut
        }
    }

    // MARK: - SessionClosed

    /// Published when the session transitions to `closed` after cooperative shutdown.
    ///
    /// Both the local TCP listener and the WebSocket connection are closed at this point.
    ///
    /// Mirrors `#SessionClosed` from `port_forward_event.cue`.
    public struct SessionClosed: Hashable, Sendable, Codable {
        /// UUIDv7 of the owning ``PortForwardSession``.
        public let sessionId: UUID
        /// RFC 3339 timestamp when the event was produced.
        public let occurredAtRFC3339: String

        public init(sessionId: UUID, occurredAtRFC3339: String) {
            self.sessionId = sessionId
            self.occurredAtRFC3339 = occurredAtRFC3339
        }
    }
}

// MARK: - PortForwardEvent convenience

extension PortForwardEvent {
    /// The `sessionId` carried by whichever variant is active.
    public var sessionId: UUID {
        switch self {
        case .sessionOpened(let e): e.sessionId
        case .sessionFailed(let e): e.sessionId
        case .listenerBound(let e): e.sessionId
        case .listenerClosed(let e): e.sessionId
        case .connectionAccepted(let e): e.sessionId
        case .bytesTransferred(let e): e.sessionId
        case .sessionClosed(let e): e.sessionId
        }
    }

    /// The `occurredAtRFC3339` timestamp carried by whichever variant is active.
    public var occurredAtRFC3339: String {
        switch self {
        case .sessionOpened(let e): e.occurredAtRFC3339
        case .sessionFailed(let e): e.occurredAtRFC3339
        case .listenerBound(let e): e.occurredAtRFC3339
        case .listenerClosed(let e): e.occurredAtRFC3339
        case .connectionAccepted(let e): e.occurredAtRFC3339
        case .bytesTransferred(let e): e.occurredAtRFC3339
        case .sessionClosed(let e): e.occurredAtRFC3339
        }
    }
}
