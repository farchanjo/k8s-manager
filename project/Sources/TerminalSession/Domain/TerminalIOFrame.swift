// Domain/TerminalIOFrame.swift — terminal_session bounded context
// DDD role: ValueObject (discriminated union)
// CUE source: docs/arch/contexts/terminal_session/schemas/terminal_io_frame.cue
// ADR ref: ADR-0017 §Channel map

import Foundation

// MARK: - ChannelByte

/// Channel numbers defined by the `v5.channel.k8s.io` subprotocol.
///
/// Every WebSocket binary frame carries a 1-byte channel prefix. The domain
/// uses this enum instead of raw integers to prevent off-by-one channel
/// misidentification (see ADR-0017 negative consequences).
public enum ChannelByte: UInt8, Hashable, Sendable {
    case stdin  = 0x00
    case stdout = 0x01
    case stderr = 0x02
    /// Error and exit-code channel — present in v5 only.
    case error  = 0x03
    /// Resize events (bidirectional).
    case resize = 0x04
}

// MARK: - TerminalIOFrame

/// Discriminated union of the five channel-specific frame types.
///
/// Constructed by `TerminalSessionActor` from raw WebSocket frames on receive,
/// and from UI events on send. Immutable — all variants are value types.
///
/// Direction constraints (per CUE schema):
/// - `.stdin` and `.resize` are **outbound-only** (client → server).
/// - `.stdout`, `.stderr`, and `.error` are **inbound-only** (server → client).
public enum TerminalIOFrame: Hashable, Sendable {
    /// Raw bytes from the operator's keyboard to the remote process stdin.
    case stdin(StdinFrame)
    /// Raw bytes from the remote process stdout stream.
    case stdout(StdoutFrame)
    /// Raw bytes from the remote process stderr stream.
    case stderr(StderrFrame)
    /// JSON error/exit-code payload from channel 3 (v5 only).
    case error(ErrorFrame)
    /// Terminal resize event (debounced to 100 ms in `TerminalSessionActor`).
    case resize(ResizeFrame)

    /// The channel this frame belongs to.
    public var channel: ChannelByte {
        switch self {
        case .stdin:  .stdin
        case .stdout: .stdout
        case .stderr: .stderr
        case .error:  .error
        case .resize: .resize
        }
    }

    /// The session identifier this frame belongs to.
    public var sessionId: UUID {
        switch self {
        case .stdin(let f):  f.sessionId
        case .stdout(let f): f.sessionId
        case .stderr(let f): f.sessionId
        case .error(let f):  f.sessionId
        case .resize(let f): f.sessionId
        }
    }
}

// MARK: - StdinFrame

/// Raw bytes from the operator's keyboard to the remote process stdin.
///
/// Mirrors `#StdinFrame`. Outbound-only (channel 0).
public struct StdinFrame: Hashable, Sendable {
    /// UUIDv7 of the owning `TerminalSession`.
    public let sessionId: UUID
    /// Raw bytes to transmit. The actor prepends the channel byte `0x00`
    /// before writing to the WebSocket.
    public let bytes: Data

    public init(sessionId: UUID, bytes: Data) {
        self.sessionId = sessionId
        self.bytes = bytes
    }
}

// MARK: - StdoutFrame

/// Raw bytes from the remote process stdout stream.
///
/// Mirrors `#StdoutFrame`. Inbound-only (channel 1).
public struct StdoutFrame: Hashable, Sendable {
    /// UUIDv7 of the owning `TerminalSession`.
    public let sessionId: UUID
    /// Payload bytes after stripping the channel-byte prefix.
    public let bytes: Data

    public init(sessionId: UUID, bytes: Data) {
        self.sessionId = sessionId
        self.bytes = bytes
    }
}

// MARK: - StderrFrame

/// Raw bytes from the remote process stderr stream.
///
/// Mirrors `#StderrFrame`. Inbound-only (channel 2).
public struct StderrFrame: Hashable, Sendable {
    /// UUIDv7 of the owning `TerminalSession`.
    public let sessionId: UUID
    /// Payload bytes after stripping the channel-byte prefix.
    public let bytes: Data

    public init(sessionId: UUID, bytes: Data) {
        self.sessionId = sessionId
        self.bytes = bytes
    }
}

// MARK: - ErrorFrame

/// JSON-encoded error or exit-code payload from channel 3 (v5.channel.k8s.io).
///
/// Mirrors `#ErrorFrame`. Inbound-only (channel 3).
/// The most common payloads are:
/// - `{"ExitCode":<int>}` — the remote process exited.
/// - `{"message":"<text>"}` — an API-level error (e.g. container not found).
public struct ErrorFrame: Hashable, Sendable {
    /// UUIDv7 of the owning `TerminalSession`.
    public let sessionId: UUID
    /// Raw UTF-8 JSON text from the API server on channel 3.
    public let json: String

    public init(sessionId: UUID, json: String) {
        self.sessionId = sessionId
        self.json = json
    }

    /// Attempts to extract `{"ExitCode":<int>}` from the payload.
    ///
    /// Returns `nil` when the payload is a message-style error rather than
    /// an exit-code notification.
    public func exitCode() -> Int? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = dict["ExitCode"] as? Int else {
            return nil
        }
        return code
    }
}

// MARK: - ResizeFrame

/// Terminal resize event carried on channel 4.
///
/// Mirrors `#ResizeFrame`. Outbound-only. The on-wire payload after the channel
/// byte is UTF-8 JSON: `{"Width":<int>,"Height":<int>}`.
/// `TerminalSessionActor` debounces to 100 ms before constructing this frame.
public struct ResizeFrame: Hashable, Sendable {
    /// UUIDv7 of the owning `TerminalSession`.
    public let sessionId: UUID
    /// New terminal height in character rows. Must be >= 1.
    public let rows: Int
    /// New terminal width in character columns. Must be >= 1.
    public let cols: Int

    public init(sessionId: UUID, rows: Int, cols: Int) {
        precondition(rows >= 1, "rows must be >= 1")
        precondition(cols >= 1, "cols must be >= 1")
        self.sessionId = sessionId
        self.rows = rows
        self.cols = cols
    }

    /// Serialises the resize payload to the wire format required by the exec API.
    ///
    /// Returns `[0x04] + UTF-8 JSON` as `Data`. The channel byte is included so
    /// the caller can pass the result directly to `URLSessionWebSocketTask.send`.
    public func wireData() -> Data {
        let json = #"{"Width":\#(cols),"Height":\#(rows)}"#
        var data = Data([ChannelByte.resize.rawValue])
        data.append(contentsOf: json.utf8)
        return data
    }
}

// MARK: - ExitCodeMapping

/// Maps a raw integer exit code to a human-readable disposition.
///
/// The v5 protocol delivers exit codes via channel 3 as `{"ExitCode":<int>}`.
/// v4 does not have a separate error channel; this enum is used exclusively for
/// codes received on channel 3.
public enum ExitCodeMapping: Hashable, Sendable {
    /// Process exited cleanly.
    case success
    /// Process exited with a non-zero code.
    case failure(code: Int)
    /// WebSocket closed without an explicit exit-code message on channel 3.
    case connectionClosed

    public init(exitCode: Int?) {
        switch exitCode {
        case .none:  self = .connectionClosed
        case .some(0): self = .success
        case .some(let c): self = .failure(code: c)
        }
    }

    /// Short description suitable for display in the terminal UI status bar.
    public var displayLabel: String {
        switch self {
        case .success:             "Process exited (0)"
        case .failure(let code):   "Process exited (\(code))"
        case .connectionClosed:    "Connection closed"
        }
    }
}
