// Ports/ResourceWatchPort.swift — resource_browser bounded context
// DDD role: Port (outbound — long-lived Kubernetes watch stream)
// ADR refs: ADR-0013 (watch verb), ADR-0012 (mutation scope)

import Foundation
import SharedKernel

// MARK: - WatchEventType

/// Incremental delta type delivered by a Kubernetes watch stream.
public enum WatchEventType: String, Hashable, Sendable, Codable {
    /// A new resource instance was created.
    case added = "ADDED"
    /// An existing resource instance was modified.
    case modified = "MODIFIED"
    /// An existing resource instance was deleted.
    case deleted = "DELETED"
    /// The watch bookmark that marks the resume point.
    case bookmark = "BOOKMARK"
}

// MARK: - ResourceWatchEvent

/// Single event emitted by a Kubernetes watch stream.
///
/// Carries the incremental delta type and the updated `ResourceListItem`
/// projection for the affected resource. `DELETED` events still carry the last
/// known projection so the UI can identify and remove the row.
public struct ResourceWatchEvent: Sendable {
    /// The type of change that occurred.
    public let type: WatchEventType

    /// The updated projection of the affected resource.
    /// For `BOOKMARK` events only `uid` and `creationTimestamp` are meaningful;
    /// other fields carry the previous values.
    public let item: ResourceListItem

    public init(type: WatchEventType, item: ResourceListItem) {
        self.type = type
        self.item = item
    }
}

// MARK: - ResourceWatchPort

/// Opens long-lived watch streams for Kubernetes resource kinds.
///
/// Each call to `watchResources` returns an `AsyncThrowingStream` that emits
/// `ResourceWatchEvent` values until the stream is cancelled or encounters an
/// unrecoverable error.
///
/// The `WatchStreamCoordinator` domain actor owns the lifecycle of active
/// streams and cancels them when the operator switches kind or namespace.
/// Reconnection with exponential back-off is managed at the actor layer, not
/// by this port.
///
/// Declared in the domain core; implemented by `SwiftkubeClientAdapter`.
public protocol ResourceWatchPort: Sendable {
    /// Opens a watch stream for the given GVK.
    ///
    /// The stream terminates when cancelled by the caller or when the server
    /// closes the connection (both cases finish the stream without an error).
    /// Transport-level errors are thrown into the stream.
    ///
    /// - Parameters:
    ///   - gvk: The Kubernetes API type to watch.
    ///   - namespace: Namespace filter. `nil` watches across all namespaces.
    ///   - contextId: The active cluster context identifier.
    ///   - resourceVersion: Optional resume point. Pass the `resourceVersion`
    ///     from the last `BOOKMARK` event to resume after a reconnect.
    /// - Returns: An `AsyncThrowingStream` of `ResourceWatchEvent` values.
    func watchResources(
        gvk: GroupVersionKind,
        namespace: String?,
        contextId: UUID,
        resourceVersion: String?
    ) -> AsyncThrowingStream<ResourceWatchEvent, Error>
}

// MARK: - ResourceWatchError

/// Errors thrown into a watch stream.
public enum ResourceWatchError: Error, Sendable {
    /// Port not registered in this process.
    case unimplemented

    /// The watch stream was closed by the server (reconnect is appropriate).
    case streamClosed(detail: String)

    /// Transport or TLS failure.
    case transportError(detail: String)

    /// The `resourceVersion` is too old and the server returned HTTP 410.
    /// The caller should re-list from scratch before re-opening the watch.
    case resourceVersionTooOld
}

// MARK: - UnimplementedResourceWatchPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedResourceWatchPort: ResourceWatchPort {
    public init() {}

    public func watchResources(
        gvk: GroupVersionKind,
        namespace: String?,
        contextId: UUID,
        resourceVersion: String?
    ) -> AsyncThrowingStream<ResourceWatchEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ResourceWatchError.unimplemented)
        }
    }
}
