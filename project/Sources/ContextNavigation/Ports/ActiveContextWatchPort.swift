// Ports/ActiveContextWatchPort.swift — context_navigation bounded context
// DDD role: Port (outbound — streaming active context changes to consumers)
// Narrative ref: domain/narrative.md §Read models exposed to other contexts

import Foundation
import SharedKernel

// MARK: - ActiveContextWatchPort

/// Streams `ActiveContextChanged` domain events to interested consumers.
///
/// Declared in the domain core; implemented by an adapter that bridges the
/// domain service output to a publish-subscribe mechanism. Consumed by
/// `app_shell` to update the title bar and menu bar without polling.
public protocol ActiveContextWatchPort: Sendable {
    /// Returns a stream of `ActiveContextChanged` events.
    ///
    /// The stream runs until cancelled; consumers use `for try await` to
    /// drive UI updates. A `Task` wrapping this stream should be cancelled
    /// when the consuming view disappears.
    ///
    /// - Returns: An `AsyncThrowingStream` that emits `ActiveContextChanged`
    ///   events indefinitely until the stream is cancelled or an error occurs.
    func watchActiveContextChanges() -> AsyncThrowingStream<ActiveContextChanged, Error>
}

// MARK: - ActiveContextWatchError

/// Errors raised by `ActiveContextWatchPort` implementations.
public enum ActiveContextWatchError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented
}

// MARK: - UnimplementedActiveContextWatchPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedActiveContextWatchPort: ActiveContextWatchPort {
    public init() {}

    public func watchActiveContextChanges() -> AsyncThrowingStream<ActiveContextChanged, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ActiveContextWatchError.unimplemented)
        }
    }
}
