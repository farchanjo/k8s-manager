// WebSocketPortForwardAdapter.swift — infrastructure adapter
// Implements: PortForwardChannelPort (PortForwarding domain)
// Wire protocol: portforward.k8s.io via Foundation.URLSessionWebSocketTask
// ADR ref: ADR-0014 (lifecycle, frame layout, close handshake)

import Foundation
import Logging
import PortForwarding

// MARK: - URLBuilder

/// Builds the `wss://` portforward subresource URL for a Kubernetes Pod.
///
/// Channel index math (ADR-0014 §Channel layout):
/// - Per-port pair: index `(portIndex * 2)` = data, `(portIndex * 2 + 1)` = error.
/// - Total channels = `ports.count * 2`.
public enum URLBuilder {
    /// Produces a portforward WebSocket URL with one `ports=<n>` param per entry.
    ///
    /// - Parameters:
    ///   - baseURL: API server base URL (scheme will be overridden to `wss`).
    ///   - namespace: Pod namespace.
    ///   - podName: Pod name.
    ///   - ports: Ordered remote port numbers; must be non-empty.
    /// - Returns: A fully-formed `wss://` URL, or `nil` when `ports` is empty or
    ///   component construction fails.
    public static func portForwardURL(
        baseURL: URL,
        namespace: String,
        podName: String,
        ports: [Int]
    ) -> URL? {
        guard !ports.isEmpty else { return nil }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = "wss"
        components?.path = "/api/v1/namespaces/\(namespace)/pods/\(podName)/portforward"
        components?.queryItems = ports.map { URLQueryItem(name: "ports", value: "\($0)") }
        return components?.url
    }
}

// MARK: - WebSocketPortForwardAdapter

/// Actor-isolated adapter that speaks the `portforward.k8s.io` WebSocket subprotocol.
///
/// One instance per ``PortForwardSession``. The owning lifecycle manager creates
/// the adapter, calls `open(namespace:podName:ports:)`, pumps `receive()` in a
/// task loop, and calls `close()` on cooperative shutdown.
///
/// Thread safety: actor isolation ensures `wsTask` is mutated from a single
/// concurrency domain; all protocol methods are `async` so callers need not be
/// on the actor's executor.
public actor WebSocketPortForwardAdapter: PortForwardChannelPort {

    // MARK: - Private state

    private let urlSession: URLSession
    private let baseURL: URL
    private var wsTask: URLSessionWebSocketTask?
    private let logger: Logger

    // MARK: - Initialisation

    /// Creates an adapter that opens connections via `urlSession`.
    ///
    /// - Parameters:
    ///   - urlSession: A `URLSession` pre-configured with TLS credentials.
    ///   - baseURL: Kubernetes API server base URL, e.g. `https://192.168.1.1:6443`.
    ///   - logger: Structured logger scoped to this adapter instance.
    public init(
        urlSession: URLSession,
        baseURL: URL,
        logger: Logger = Logger(label: "WebSocketPortForwardAdapter")
    ) {
        self.urlSession = urlSession
        self.baseURL = baseURL
        self.logger = logger
    }

    // MARK: - PortForwardChannelPort

    /// Opens a `portforward.k8s.io` WebSocket connection to the named Pod.
    public func open(namespace: String, podName: String, ports: [Int]) async throws {
        guard let url = URLBuilder.portForwardURL(
            baseURL: baseURL,
            namespace: namespace,
            podName: podName,
            ports: ports
        ) else {
            throw PortForwardChannelError.transportError(detail: "Failed to build portforward URL")
        }
        var request = URLRequest(url: url)
        request.addValue("portforward.k8s.io", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = urlSession.webSocketTask(with: request)
        wsTask = task
        task.resume()
        logger.info(
            "WebSocket portforward opened",
            metadata: ["namespace": "\(namespace)", "pod": "\(podName)", "ports": "\(ports)"]
        )
    }

    /// Encodes `frame` and sends it as a binary WebSocket message.
    public func send(_ frame: PortForwardFrame) async throws {
        guard let task = wsTask else {
            throw PortForwardChannelError.connectionClosed
        }
        do {
            try await task.send(.data(frame.encoded()))
        } catch {
            throw PortForwardChannelError.sendFailed(detail: error.localizedDescription)
        }
    }

    /// Waits for the next binary WebSocket message and decodes it as a ``PortForwardFrame``.
    public func receive() async throws -> PortForwardFrame? {
        guard let task = wsTask else {
            throw PortForwardChannelError.connectionClosed
        }
        let message: URLSessionWebSocketTask.Message
        do {
            message = try await task.receive()
        } catch {
            let nsErr = error as NSError
            if nsErr.code == URLError.cancelled.rawValue { return nil }
            throw PortForwardChannelError.receiveFailed(detail: error.localizedDescription)
        }
        return try decodedFrame(from: message)
    }

    /// Sends a WebSocket Close frame (code 1000) and releases the task.
    public func close() async {
        guard let task = wsTask else { return }
        task.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        logger.info("WebSocket portforward closed")
    }

    // MARK: - Private helpers

    private func decodedFrame(
        from message: URLSessionWebSocketTask.Message
    ) throws -> PortForwardFrame {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: throw PortForwardChannelError.malformedFrame
        }
        guard let frame = PortForwardFrame.decode(data) else {
            throw PortForwardChannelError.malformedFrame
        }
        return frame
    }
}

// MARK: - PortForwardChannelIndex

/// Helpers for the two-channel-per-port layout described in ADR-0014.
///
/// Channel numbering: Port 0 → (data=0, error=1); Port 1 → (data=2, error=3); …
public enum PortForwardChannelIndex {
    /// Returns the channel index for the data stream of the given port.
    public static func data(forPortAt portIndex: Int) -> Int { portIndex * 2 }
    /// Returns the channel index for the error stream of the given port.
    public static func error(forPortAt portIndex: Int) -> Int { portIndex * 2 + 1 }
    /// Returns the total number of channels required for `portCount` port mappings.
    public static func channelCount(forPortCount portCount: Int) -> Int { portCount * 2 }
}
