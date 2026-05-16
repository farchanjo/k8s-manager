// Ports/PodExecPort.swift — terminal_session bounded context
// DDD role: Port (secondary — outbound; WebSocket exec subresource)
// ADR ref: ADR-0017 §Decision outcome, §Protocol detail
// Implemented by: WebSocketExecAdapter (infrastructure layer)

import Foundation

// MARK: - PodExecRequest

/// Parameters passed to `PodExecPort.openExec(request:)`.
///
/// Encapsulates everything required to open a `pods/exec` WebSocket:
/// Pod coordinates, command, TTY/stdin flags, and requested subprotocol.
public struct PodExecRequest: Hashable, Sendable {
    /// Kubernetes namespace of the target Pod.
    public let namespace: String
    /// Name of the target Pod.
    public let podName: String
    /// Container to exec into. `nil` defaults to the first container in the Pod spec.
    public let containerName: String?
    /// Argv list for the exec command. Must be non-empty.
    public let command: [String]
    /// Whether a pseudo-terminal should be allocated.
    public let tty: Bool
    /// Whether stdin should be forwarded.
    public let stdin: Bool

    public init(
        namespace: String,
        podName: String,
        containerName: String? = nil,
        command: [String],
        tty: Bool,
        stdin: Bool
    ) {
        precondition(!command.isEmpty, "command must be non-empty")
        self.namespace = namespace
        self.podName = podName
        self.containerName = containerName
        self.command = command
        self.tty = tty
        self.stdin = stdin
    }
}

// MARK: - ExecConnection

/// Handle returned by `PodExecPort.openExec(request:)`.
///
/// The infra adapter fills this with everything the `TerminalSessionActor`
/// needs to drive the session — the negotiated subprotocol and an
/// `AsyncStream` of raw WebSocket binary frames for the receive loop.
public struct ExecConnection: Sendable {
    /// Subprotocol negotiated with the API server.
    public let subprotocol: ExecSubprotocol
    /// Raw inbound WebSocket binary frames (channel-byte prefix included).
    public let frames: AsyncStream<Data>
    /// Closure the actor calls to send a raw frame (channel-byte prefix included).
    public let send: @Sendable (Data) async throws -> Void
    /// Closes the underlying WebSocket connection cooperatively.
    public let close: @Sendable () async -> Void

    public init(
        subprotocol: ExecSubprotocol,
        frames: AsyncStream<Data>,
        send: @escaping @Sendable (Data) async throws -> Void,
        close: @escaping @Sendable () async -> Void
    ) {
        self.subprotocol = subprotocol
        self.frames = frames
        self.send = send
        self.close = close
    }
}

// MARK: - PodExecPort

/// Opens a WebSocket connection to the Kubernetes `pods/exec` subresource.
///
/// Declared in the domain core; implemented by `WebSocketExecAdapter` in the
/// infrastructure layer. The domain core never imports `URLSession` directly or
/// constructs `URLRequest` objects — that responsibility belongs to the adapter.
///
/// Subprotocol negotiation: the adapter requests `v5.channel.k8s.io` and falls
/// back to `v4.channel.k8s.io` when the server downgrades (per ADR-0017).
/// mTLS credential injection is handled by the adapter via `URLSessionDelegate`.
public protocol PodExecPort: Sendable {
    /// Opens a WebSocket exec connection for the given request.
    ///
    /// - Parameter request: Coordinates and flags for the exec session.
    /// - Returns: An `ExecConnection` the caller uses to drive the session.
    /// - Throws: `PodExecError` on handshake failure or unsupported subprotocol.
    func openExec(request: PodExecRequest) async throws -> ExecConnection
}

// MARK: - PodExecError

/// Errors raised by `PodExecPort` implementations.
public enum PodExecError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented
    /// WebSocket handshake failed (e.g. 401, 403, 404, or network error).
    case handshakeFailed(detail: String)
    /// The API server responded with an unsupported or missing subprotocol.
    case unsupportedSubprotocol(received: String)
    /// The WebSocket connection was closed unexpectedly.
    case connectionReset(detail: String)
}

// MARK: - UnimplementedPodExecPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedPodExecPort: PodExecPort {
    public init() {}

    public func openExec(request: PodExecRequest) async throws -> ExecConnection {
        throw PodExecError.unimplemented
    }
}
