// WebSocketPortForwardAdapter.swift — infrastructure adapter placeholder
// Implements: PortForwardPort from PortForwarding
// Library: Foundation.URLSessionWebSocketTask (Apple system framework — no SwiftPM package)
// Status: skeleton; port implementations pending domain ports definition.
import Foundation

/// Namespace marker for the WebSocketPortForwardAdapter adapter target.
///
/// Concrete actor types implementing the domain ports land under this enum
/// in subsequent rounds. This file exists so the target compiles cleanly
/// under Swift 6 strict concurrency with the imported infrastructure library.
public enum WebSocketPortForwardAdapter: Sendable {
    public static let moduleVersion = "0.0.1-skeleton"
}
