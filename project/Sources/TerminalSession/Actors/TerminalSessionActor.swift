// Actors/TerminalSessionActor.swift — terminal_session bounded context
// DDD role: DomainService (actor — owns one PTY session lifecycle)
// ADR refs: ADR-0011 (actor model), ADR-0017 (terminal sessions)
// CUE source: docs/arch/contexts/terminal_session/schemas/terminal_session.cue

import Foundation
import Dependencies
import Logging

// MARK: - TerminalSessionError

/// Errors raised by `TerminalSessionActor`.
public enum TerminalSessionError: Error, Sendable {
    /// `open()` was called on a session that is not in the `.opening` state.
    case invalidState(current: SessionStatus)
    /// `sendInput(_:)` or `sendResize(_:)` called on a non-open session.
    case sessionNotOpen
    /// The underlying exec connection could not send the frame.
    case sendFailed(detail: String)
}

// MARK: - TerminalSessionActor

/// Owns one PTY session: drives the lifecycle state machine, routes frames,
/// and exposes an `AsyncThrowingStream` for UI consumers.
///
/// One actor instance per session. Actors are not pooled or reused across
/// sessions (per ADR-0017). All mutable state is actor-isolated; no locks
/// are needed.
///
/// Lifecycle:
/// ```
/// opening → open → closing → closed
/// opening → error
/// open    → error
/// ```
public actor TerminalSessionActor {

    // MARK: State

    /// Current aggregate snapshot. Updated on every lifecycle transition.
    private(set) public var session: TerminalSession

    /// Active connection returned by `PodExecPort`. `nil` before `open()`.
    private var connection: ExecConnection?

    /// Continuation driving the `outputStream()` `AsyncThrowingStream`.
    private var outputContinuation: AsyncThrowingStream<TerminalIOFrame, Error>.Continuation?

    /// Background task running the receive loop.
    private var receiveTask: Task<Void, Never>?

    /// Timestamp of the last inbound or outbound frame. Used by idle timeout.
    private var lastActivityAt: Date = Date()

    /// Pending resize debounce task (100 ms window, per ADR-0017).
    private var resizeDebounceTask: Task<Void, Never>?

    private let logger: Logger

    // MARK: Init

    /// Creates the actor for `session`. Status must be `.opening`.
    ///
    /// - Parameter session: The newly created aggregate (status `.opening`).
    public init(session: TerminalSession, logger: Logger = .init(label: "terminal.actor")) {
        self.session = session
        self.logger = logger
    }

    // MARK: Open

    /// Opens the WebSocket exec connection and transitions the session to `.open`.
    ///
    /// Calls `PodExecPort.openExec(request:)` via the dependency container,
    /// records the negotiated subprotocol on the aggregate, starts the receive
    /// loop, and saves the updated session via `TerminalRepositoryPort`.
    ///
    /// - Throws: `TerminalSessionError.invalidState` when not `.opening`,
    ///   or a `PodExecError` on WebSocket handshake failure.
    public func open() async throws {
        guard session.status == .opening else {
            throw TerminalSessionError.invalidState(current: session.status)
        }
        @Dependency(\.podExec) var podExec
        @Dependency(\.terminalRepository) var repository

        let request = buildExecRequest()
        let conn = try await podExec.openExec(request: request)
        connection = conn
        session = session
            .withSubprotocol(conn.subprotocol)
            .withStatus(.open)
        try? await repository.save(session)
        startReceiveLoop(connection: conn)
        logger.info("TerminalSessionActor: session \(session.id) opened [\(conn.subprotocol.rawValue)]")
    }

    // MARK: Send input

    /// Sends raw keyboard bytes to the remote process stdin (channel 0).
    ///
    /// Prepends the channel byte `0x00` before writing to the wire.
    ///
    /// - Parameter data: Raw bytes from the operator's keyboard.
    /// - Throws: `TerminalSessionError.sessionNotOpen` when not `.open`.
    public func sendInput(_ data: Data) async throws {
        guard session.status == .open, let conn = connection else {
            throw TerminalSessionError.sessionNotOpen
        }
        var frame = Data([ChannelByte.stdin.rawValue])
        frame.append(data)
        try await conn.send(frame)
        lastActivityAt = Date()
    }

    // MARK: Send resize

    /// Schedules a debounced resize event on channel 4 (100 ms window).
    ///
    /// Intermediate resize events within the debounce window are discarded;
    /// only the last size before the window closes is transmitted
    /// (per ADR-0017 §Resize debouncing).
    ///
    /// - Parameter size: The new terminal dimensions.
    /// - Throws: `TerminalSessionError.sessionNotOpen` when not `.open`.
    public func sendResize(_ size: TerminalSize) async throws {
        guard session.status == .open else {
            throw TerminalSessionError.sessionNotOpen
        }
        resizeDebounceTask?.cancel()
        resizeDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await self.flushResize(size: size)
        }
    }

    // MARK: Output stream

    /// Returns a stream of inbound frames from the remote process.
    ///
    /// The stream yields `.stdout`, `.stderr`, `.error`, and `.resize` frames
    /// as they arrive from the WebSocket receive loop. It finishes when the
    /// session closes or encounters an unrecoverable error.
    ///
    /// - Returns: An `AsyncThrowingStream` of `TerminalIOFrame` values.
    public func outputStream() -> AsyncThrowingStream<TerminalIOFrame, Error> {
        AsyncThrowingStream { continuation in
            self.outputContinuation = continuation
        }
    }

    // MARK: Close

    /// Cooperatively closes the session within the 200 ms budget (ADR-0017).
    ///
    /// Transitions to `.closing`, cancels the receive loop, sends the
    /// WebSocket close frame, and transitions to `.closed`. Saves the final
    /// aggregate state via `TerminalRepositoryPort`.
    public func close() async {
        guard session.status == .open || session.status == .opening else { return }
        session = session.withStatus(.closing)
        resizeDebounceTask?.cancel()
        receiveTask?.cancel()
        await connection?.close()
        connection = nil
        session = session.withStatus(.closed)
        outputContinuation?.finish()
        outputContinuation = nil
        @Dependency(\.terminalRepository) var repository
        try? await repository.save(session)
        logger.info("TerminalSessionActor: session \(session.id) closed")
    }

    // MARK: Private helpers

    private func buildExecRequest() -> PodExecRequest {
        let target: PodTarget
        if case .pod(let t) = session.targetRef {
            target = t
        } else {
            target = PodTarget(namespace: "default", podName: "unknown")
        }
        return PodExecRequest(
            namespace: target.namespace,
            podName: target.podName,
            containerName: target.containerName,
            command: session.command,
            tty: session.tty,
            stdin: session.stdin
        )
    }

    private func startReceiveLoop(connection: ExecConnection) {
        receiveTask = Task {
            for await rawFrame in connection.frames {
                guard !Task.isCancelled else { break }
                await self.handleInboundFrame(rawFrame)
            }
            await self.handleConnectionEnd()
        }
    }

    private func handleInboundFrame(_ raw: Data) {
        guard let channelByte = raw.first,
              let channel = ChannelByte(rawValue: channelByte) else { return }
        let payload = raw.dropFirst()
        lastActivityAt = Date()
        let frame: TerminalIOFrame
        switch channel {
        case .stdout:
            frame = .stdout(StdoutFrame(sessionId: session.id, bytes: Data(payload)))
        case .stderr:
            frame = .stderr(StderrFrame(sessionId: session.id, bytes: Data(payload)))
        case .error:
            let json = String(data: Data(payload), encoding: .utf8) ?? ""
            frame = .error(ErrorFrame(sessionId: session.id, json: json))
        default:
            return
        }
        outputContinuation?.yield(frame)
    }

    private func handleConnectionEnd() {
        guard session.status != .closed && session.status != .closing else { return }
        session = session.withStatus(.closed)
        outputContinuation?.finish()
        outputContinuation = nil
        @Dependency(\.terminalRepository) var repository
        Task { try? await repository.save(self.session) }
    }

    private func flushResize(size: TerminalSize) async {
        guard session.status == .open, let conn = connection else { return }
        let resizeFrame = ResizeFrame(sessionId: session.id, rows: size.rows, cols: size.cols)
        let wire = resizeFrame.wireData()
        try? await conn.send(wire)
        session = session.withSize(rows: size.rows, cols: size.cols, lastActivityAt: ISO8601DateFormatter().string(from: Date()))
        lastActivityAt = Date()
        let frame = TerminalIOFrame.resize(resizeFrame)
        outputContinuation?.yield(frame)
    }
}

// MARK: - TerminalSize

/// Terminal dimensions passed to `TerminalSessionActor.sendResize(_:)`.
public struct TerminalSize: Hashable, Sendable {
    /// Terminal height in character rows. Must be >= 1.
    public let rows: Int
    /// Terminal width in character columns. Must be >= 1.
    public let cols: Int

    /// Creates a `TerminalSize` with the given dimensions.
    public init(rows: Int, cols: Int) {
        precondition(rows >= 1, "rows must be >= 1")
        precondition(cols >= 1, "cols must be >= 1")
        self.rows = rows
        self.cols = cols
    }
}
