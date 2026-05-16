// WebSocketExecAdapter.swift — infrastructure adapter for pods/exec via WebSocket
// Implements: PodExecPort (TerminalSession domain)
// Transport: Foundation.URLSessionWebSocketTask
// Protocol: v5.channel.k8s.io (fallback: v4.channel.k8s.io)
// ADR ref: ADR-0017

import Foundation
import Logging
import TerminalSession

// MARK: - WebSocketExecAdapter

/// Infrastructure adapter that opens a `pods/exec` WebSocket connection using
/// `URLSessionWebSocketTask` and bridges it to the `PodExecPort` contract.
///
/// The adapter requests `v5.channel.k8s.io` and accepts a server downgrade to
/// `v4.channel.k8s.io`. Frame framing follows the channel-multiplexing spec in
/// ADR-0017 §Protocol detail: first byte = channel number, remaining bytes = payload.
public actor WebSocketExecAdapter: PodExecPort {

    // MARK: - State

    private let urlSession: URLSession
    private let apiServerBase: URL
    private let logger: Logger

    // MARK: - Init

    /// Creates the adapter.
    ///
    /// - Parameters:
    ///   - urlSession: A `URLSession` already configured with cluster TLS credentials
    ///     via its delegate or configuration.
    ///   - apiServerBase: The base URL of the Kubernetes API server, e.g.
    ///     `https://k8s.example.com:6443`. Must use `https` scheme.
    public init(urlSession: URLSession, apiServerBase: URL) {
        self.urlSession = urlSession
        self.apiServerBase = apiServerBase
        self.logger = Logger(label: "WebSocketExecAdapter")
    }

    // MARK: - PodExecPort

    /// Opens a `pods/exec` WebSocket and returns an `ExecConnection`.
    ///
    /// Builds the exec URL, attaches `Sec-WebSocket-Protocol: v5.channel.k8s.io`,
    /// starts the task, reads the negotiated subprotocol from the response, and
    /// starts the receive loop inside an `AsyncStream`.
    public func openExec(request: PodExecRequest) async throws -> ExecConnection {
        let url = try buildExecURL(request: request)
        let wsRequest = buildWebSocketRequest(url: url)

        let task = urlSession.webSocketTask(with: wsRequest)
        task.resume()

        let subprotocol = try await resolveSubprotocol(task: task)
        logger.info("exec WebSocket open", metadata: [
            "pod": "\(request.namespace)/\(request.podName)",
            "subprotocol": "\(subprotocol.rawValue)",
        ])

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        let receiveTask = Task { [logger] in
            await Self.receiveLoop(task: task, continuation: continuation, logger: logger)
        }

        let send: @Sendable (Data) async throws -> Void = { [logger] data in
            do {
                try await task.send(.data(data))
            } catch {
                logger.error("send failed: \(error)")
                throw PodExecError.connectionReset(detail: error.localizedDescription)
            }
        }

        let close: @Sendable () async -> Void = {
            receiveTask.cancel()
            task.cancel(with: .goingAway, reason: nil)
        }

        return ExecConnection(
            subprotocol: subprotocol,
            frames: stream,
            send: send,
            close: close
        )
    }

    // MARK: - URL construction

    private func buildExecURL(request: PodExecRequest) throws -> URL {
        var components = URLComponents(
            url: apiServerBase,
            resolvingAgainstBaseURL: false
        ) ?? URLComponents()

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/api/v1/namespaces/\(request.namespace)/pods/\(request.podName)/exec"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "stdin",  value: request.stdin ? "true" : "false"),
            URLQueryItem(name: "stdout", value: "true"),
            URLQueryItem(name: "stderr", value: "true"),
            URLQueryItem(name: "tty",    value: request.tty ? "true" : "false"),
        ]
        if let container = request.containerName {
            queryItems.append(URLQueryItem(name: "container", value: container))
        }
        for arg in request.command {
            queryItems.append(URLQueryItem(name: "command", value: arg))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw PodExecError.handshakeFailed(
                detail: "Could not build exec URL for \(request.podName)"
            )
        }
        return url
    }

    private func buildWebSocketRequest(url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(ExecSubprotocol.v5.rawValue, forHTTPHeaderField: "Sec-WebSocket-Protocol")
        return req
    }

    // MARK: - Subprotocol resolution

    /// Reads the negotiated subprotocol from the task HTTP response headers.
    ///
    /// A short `Task.sleep` allows the handshake to complete. If the header is
    /// absent the server is pre-1.31 and we default to v4.
    private func resolveSubprotocol(task: URLSessionWebSocketTask) async throws -> ExecSubprotocol {
        try await Task.sleep(for: .milliseconds(50))

        guard let httpResponse = task.response as? HTTPURLResponse,
              let header = httpResponse.allHeaderFields["Sec-WebSocket-Protocol"] as? String else {
            logger.debug("Sec-WebSocket-Protocol header absent; defaulting to v4")
            return .v4
        }

        switch header {
        case ExecSubprotocol.v5.rawValue: return .v5
        case ExecSubprotocol.v4.rawValue: return .v4
        default:
            throw PodExecError.unsupportedSubprotocol(received: header)
        }
    }

    // MARK: - Receive loop

    /// Drains frames from the WebSocket task until cancelled or the connection closes.
    ///
    /// Binary frames are forwarded verbatim (channel byte included) to the stream.
    /// Channel byte `0xff` signals a v5 close-stream half; the loop finishes gracefully.
    private static func receiveLoop(
        task: URLSessionWebSocketTask,
        continuation: AsyncStream<Data>.Continuation,
        logger: Logger
    ) async {
        defer { continuation.finish() }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .data(let data):
                    guard !data.isEmpty else { continue }
                    if data.first == 0xFF {
                        logger.debug("v5 close-stream half received; finishing stream")
                        return
                    }
                    continuation.yield(data)
                case .string(let text):
                    logger.debug("Unexpected text frame: \(text)")
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    logger.error("WebSocket receive error: \(error)")
                }
                return
            }
        }
    }
}

// MARK: - Frame helpers (pure functions, testable without network)

/// Encodes a `Data` payload into a wire frame by prepending the channel byte.
///
/// - Parameters:
///   - channel: Channel byte prefix (`0x00`-`0x04`).
///   - payload: Raw payload bytes.
/// - Returns: `[channel] + payload` as `Data`.
public func encodeExecFrame(channel: ChannelByte, payload: Data) -> Data {
    var frame = Data([channel.rawValue])
    frame.append(payload)
    return frame
}

/// Decodes a raw WebSocket binary frame into a `(channel, payload)` pair.
///
/// - Parameter frame: Raw frame bytes (channel byte at index 0).
/// - Returns: `(ChannelByte, Data)` when the channel byte is recognised; `nil` otherwise.
public func decodeExecFrame(frame: Data) -> (channel: ChannelByte, payload: Data)? {
    guard let first = frame.first,
          let channel = ChannelByte(rawValue: first) else { return nil }
    return (channel, frame.dropFirst())
}
