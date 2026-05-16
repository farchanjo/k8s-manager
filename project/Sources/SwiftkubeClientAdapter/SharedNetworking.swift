// SharedNetworking.swift — process-wide NIO + HTTP client singleton
// Bounded context: infrastructure cross-cutting
// ADR ref: ADR-0007 (Connection pool keep-alive — single shared HTTPClient + MTELG)

import AsyncHTTPClient
import Foundation
import NIO

// MARK: - SharedNetworking

/// Process-wide singleton providing a shared `MultiThreadedEventLoopGroup`
/// and `HTTPClient` so that every infrastructure adapter reuses the same
/// connection pool and NIO thread pool instead of creating per-instance groups.
///
/// Thread safety: both stored properties are initialized once via Swift's
/// lazy `static let` guarantee (dispatch_once semantics). All mutations go
/// through `AsyncHTTPClient` and NIO's own synchronization.
///
/// Lifecycle: call `shutdown()` exactly once, from the app-termination hook
/// (`AppActivationDelegate.applicationWillTerminate`). After `shutdown()` returns,
/// no further network operations should be issued against either property.
public enum SharedNetworking {

    // MARK: - Shared resources

    /// Shared NIO event loop group sized to half the available processor count
    /// (minimum 2 threads) per ADR-0007.
    public static let eventLoopGroup: MultiThreadedEventLoopGroup = {
        let threadCount = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        return MultiThreadedEventLoopGroup(numberOfThreads: threadCount)
    }()

    /// Shared `AsyncHTTPClient` backed by `eventLoopGroup`.
    ///
    /// Configuration (ADR-0007):
    /// - Connect timeout: 10 s
    /// - Read timeout: 30 s
    /// - Redirect: follow up to 5 hops, no cycles
    /// - Idle connection pool timeout: 45 s
    public static let httpClient: HTTPClient = {
        let configuration = HTTPClient.Configuration(
            timeout: .init(connect: .seconds(10), read: .seconds(30)),
            redirectConfiguration: .follow(max: 5, allowCycles: false),
            connectionPool: .init(idleTimeout: .seconds(45))
        )
        return HTTPClient(
            eventLoopGroupProvider: .shared(eventLoopGroup),
            configuration: configuration
        )
    }()

    // MARK: - Lifecycle

    /// Shuts down the shared `HTTPClient` and then the `MultiThreadedEventLoopGroup`.
    ///
    /// Safe to call from `AppActivationDelegate.applicationWillTerminate`.
    /// Must be called at most once per process lifetime.
    public static func shutdown() async throws {
        try await httpClient.shutdown()
        try await eventLoopGroup.shutdownGracefully()
    }
}
