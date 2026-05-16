// Ports/PortForwardChannelPort.swift — port_forwarding bounded context
// DDD role: Port (secondary — outbound, WebSocket pod/portforward wire protocol)
// ADR ref: ADR-0014 (portforward.k8s.io subprotocol, binary frame layout)
// Narrative ref: docs/arch/contexts/port_forwarding/domain/narrative.md §Tactical roles

import Foundation

// MARK: - PortForwardFrame

/// A decoded binary frame from the `portforward.k8s.io` WebSocket subprotocol.
///
/// Wire layout (ADR-0014 §Wire protocol detail):
/// ```
/// Byte 0: portIndex  — 0-based index of the PortMapping in the upgrade URL
/// Byte 1: streamType — 0x00 = data, 0x01 = error
/// Byte 2…: payload   — may be empty (zero-byte data frame = EOF)
/// ```
///
/// Note on byte order: byte 0 is `portIndex`; byte 1 is `streamType`. An earlier
/// draft of ADR-0014 had these reversed. All code in this module uses the corrected
/// order verified against the Kubernetes source at
/// `staging/src/k8s.io/apiserver/pkg/util/wsstream/conn.go`.
public struct PortForwardFrame: Sendable {
    /// 0-based index of the ``PortMapping`` this frame belongs to.
    public let portIndex: UInt8
    /// Indicates whether this frame carries data payload or an error message.
    public let streamType: StreamType
    /// Payload bytes. An empty `Data` on a ``StreamType/data`` frame signals
    /// EOF for that port's data direction (graceful half-close).
    public let payload: Data

    public init(portIndex: UInt8, streamType: StreamType, payload: Data) {
        self.portIndex = portIndex
        self.streamType = streamType
        self.payload = payload
    }

    // MARK: - StreamType

    /// Stream channel within a single port index.
    ///
    /// Mirrors the `streamType` byte in the `portforward.k8s.io` frame header.
    public enum StreamType: UInt8, Sendable {
        /// Bidirectional payload bytes for the given port (byte value `0x00`).
        case data = 0x00
        /// Server-to-client error message for the given port (byte value `0x01`).
        case error = 0x01
    }

    // MARK: Wire encoding / decoding

    /// Encodes this frame into a 2-byte header followed by the payload, ready for
    /// transmission as a binary WebSocket message.
    ///
    /// - Returns: `Data` where `data[0] == portIndex` and `data[1] == streamType.rawValue`.
    public func encoded() -> Data {
        var out = Data(capacity: 2 + payload.count)
        out.append(portIndex)
        out.append(streamType.rawValue)
        out.append(contentsOf: payload)
        return out
    }

    /// Decodes a binary WebSocket message into a ``PortForwardFrame``.
    ///
    /// - Parameter data: Raw bytes received from the WebSocket task. Must be at least
    ///   2 bytes (the header); fewer bytes is treated as a malformed frame.
    /// - Returns: A decoded ``PortForwardFrame``, or `nil` if `data` is shorter than
    ///   the 2-byte header or carries an unrecognised `streamType` byte.
    public static func decode(_ data: Data) -> PortForwardFrame? {
        guard data.count >= 2 else { return nil }
        let portIndex = data[data.startIndex]
        let streamTypeByte = data[data.startIndex.advanced(by: 1)]
        guard let streamType = StreamType(rawValue: streamTypeByte) else { return nil }
        let payload = data.advanced(by: 2)
        return PortForwardFrame(portIndex: portIndex, streamType: streamType, payload: payload)
    }
}

// MARK: - PortForwardChannelPort

/// Secondary port: opens a `portforward.k8s.io` WebSocket connection to a
/// Kubernetes Pod's portforward subresource.
///
/// Declared in the domain core; implemented by `WebSocketPortForwardAdapter` in
/// infrastructure. The domain core never imports `Foundation.URLSession` or any
/// adapter-layer type. Credential injection (mTLS, bearer token, exec-plugin) is
/// handled entirely inside the adapter.
///
/// One `PortForwardChannelPort` instance is created per ``PortForwardSession``.
/// The connection is torn down when the owning session reaches `closed` or `error`.
public protocol PortForwardChannelPort: Sendable {
    /// Opens a WebSocket connection to the Kubernetes portforward subresource for
    /// `podName` in `namespace`, negotiating the `portforward.k8s.io` subprotocol.
    ///
    /// The `ports` list determines the `portIndex` assignment: index 0 in `ports`
    /// corresponds to `portIndex 0` in all subsequent frames.
    ///
    /// - Parameters:
    ///   - namespace: Kubernetes namespace of the target Pod.
    ///   - podName: Name of the target Pod.
    ///   - ports: Ordered list of remote port numbers to forward. Must be non-empty.
    ///     The order of values here must match the order of ``PortMapping`` entries
    ///     in the owning ``PortForwardSession``.
    /// - Throws: ``PortForwardChannelError`` on upgrade failure or transport error.
    func open(namespace: String, podName: String, ports: [Int]) async throws

    /// Sends a binary frame to the Kubernetes API server.
    ///
    /// - Parameter frame: The frame to transmit, encoded via ``PortForwardFrame/encoded()``.
    /// - Throws: ``PortForwardChannelError/connectionClosed`` if the WebSocket is no
    ///   longer open, or ``PortForwardChannelError/sendFailed`` on transport error.
    func send(_ frame: PortForwardFrame) async throws

    /// Receives the next binary frame from the Kubernetes API server.
    ///
    /// Blocks asynchronously until a frame arrives, the connection closes, or a
    /// transport error occurs.
    ///
    /// - Returns: The next decoded ``PortForwardFrame``, or `nil` when the server
    ///   has sent a normal WebSocket Close frame (end of stream).
    /// - Throws: ``PortForwardChannelError/receiveFailed`` on transport error, or
    ///   ``PortForwardChannelError/malformedFrame`` if the received bytes cannot be
    ///   decoded as a valid `portforward.k8s.io` frame.
    func receive() async throws -> PortForwardFrame?

    /// Initiates a graceful WebSocket close handshake.
    ///
    /// Sends a Close frame with code 1000 (normal closure) and waits up to 200 ms
    /// for the server's echo before discarding the underlying task (ADR-0014
    /// §WebSocket close handshake).
    func close() async
}

// MARK: - PortForwardChannelError

/// Errors raised by ``PortForwardChannelPort`` implementations.
public enum PortForwardChannelError: Error, Sendable {
    /// Port has not been registered in this process.
    case unimplemented
    /// The WebSocket upgrade request was rejected by the API server.
    case upgradeRejected(statusCode: Int, detail: String)
    /// A transport-level error occurred before a response was received.
    case transportError(detail: String)
    /// The connection is no longer open; no frames can be sent or received.
    case connectionClosed
    /// A `send` call failed for a reason other than connection closure.
    case sendFailed(detail: String)
    /// A `receive` call failed for a reason other than normal closure.
    case receiveFailed(detail: String)
    /// The received bytes did not conform to the 2-byte `portforward.k8s.io`
    /// frame header layout.
    case malformedFrame
}

// MARK: - UnimplementedPortForwardChannelPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedPortForwardChannelPort: PortForwardChannelPort {
    public init() {}

    public func open(namespace: String, podName: String, ports: [Int]) async throws {
        throw PortForwardChannelError.unimplemented
    }

    public func send(_ frame: PortForwardFrame) async throws {
        throw PortForwardChannelError.unimplemented
    }

    public func receive() async throws -> PortForwardFrame? {
        throw PortForwardChannelError.unimplemented
    }

    public func close() async {}
}
