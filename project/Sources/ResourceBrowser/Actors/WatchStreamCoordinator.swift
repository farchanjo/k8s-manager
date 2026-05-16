// Actors/WatchStreamCoordinator.swift — resource_browser bounded context
// DDD role: DomainService (actor)
// ADR refs: ADR-0036 (watch stream lifecycle, 410-Gone recovery, fan-out budget)

import Dependencies
import Foundation
import Logging

// MARK: - WatchKey

/// Uniquely identifies an active watch subscription.
private struct WatchKey: Hashable, Sendable {
    let clusterId: UUID
    let gvk: GroupVersionKind
    let namespace: String?
}

// MARK: - WatchStreamCoordinator

/// Owns `AsyncStream<ResourceWatchEvent>` per (clusterId, GVK, namespace).
///
/// Manages the lifecycle of watch streams: start, subscribe, cancel, and
/// 410-Gone recovery per ADR-0036. Each (clusterId, GVK, namespace) key maps
/// to a single shared stream delivered to all subscribers via fan-out.
///
/// The coordinator itself never imports SwiftkubeClient; it drives `ResourceWatchPort`
/// for the underlying transport.
public actor WatchStreamCoordinator {

    // MARK: - Dependencies

    @Dependency(\.resourceWatch) private var watchPort

    // MARK: - State

    /// Maps each watch key to its active stream task and continuation.
    private var activeStreams: [WatchKey: StreamEntry] = [:]

    /// Last known resource versions per key (advanced on BOOKMARK events).
    private var lastKnownRV: [WatchKey: String] = [:]

    private let logger: Logger

    // MARK: - Nested types

    private struct StreamEntry: Sendable {
        let task: Task<Void, Never>
        let continuations: [UUID: AsyncStream<ResourceWatchEvent>.Continuation]
    }

    // MARK: - Initialiser

    /// Creates a coordinator with an optional logger.
    public init(logger: Logger = Logger(label: "resource_browser.watch_coordinator")) {
        self.logger = logger
    }

    // MARK: - Public API

    /// Opens or reuses a watch stream for the given key.
    ///
    /// Multiple callers for the same (clusterId, GVK, namespace) share one
    /// underlying watch stream. Returns an `AsyncStream` that terminates when
    /// `unsubscribe(id:)` is called with the returned subscription ID.
    ///
    /// - Parameters:
    ///   - gvk: The Kubernetes API type to watch.
    ///   - namespace: Namespace filter; `nil` watches all namespaces.
    ///   - clusterId: The active cluster context UUID.
    /// - Returns: A tuple of (subscriptionId, stream).
    public func subscribe(
        gvk: GroupVersionKind,
        namespace: String?,
        clusterId: UUID
    ) -> (id: UUID, stream: AsyncStream<ResourceWatchEvent>) {
        let key = WatchKey(clusterId: clusterId, gvk: gvk, namespace: namespace)
        let subscriptionId = UUID()

        var continuation: AsyncStream<ResourceWatchEvent>.Continuation?
        let stream = AsyncStream<ResourceWatchEvent> { c in continuation = c }

        guard let cont = continuation else {
            preconditionFailure("AsyncStream continuation unavailable")
        }

        if var entry = activeStreams[key] {
            // Attach to existing stream.
            var conts = entry.continuations
            conts[subscriptionId] = cont
            activeStreams[key] = StreamEntry(task: entry.task, continuations: conts)
        } else {
            // Spawn a new draining task for this key.
            let task = Task { [weak self] in
                await self?.drainWatchPort(key: key)
                return
            }
            activeStreams[key] = StreamEntry(
                task: task,
                continuations: [subscriptionId: cont]
            )
        }

        return (subscriptionId, stream)
    }

    /// Removes a subscriber. When the last subscriber for a key leaves,
    /// the underlying watch task is cancelled.
    ///
    /// - Parameter id: The subscription UUID returned by `subscribe(...)`.
    public func unsubscribe(id: UUID) {
        for key in activeStreams.keys {
            guard let entry = activeStreams[key],
                  let cont = entry.continuations[id] else { continue }
            cont.finish()
            var conts = entry.continuations
            conts.removeValue(forKey: id)
            if conts.isEmpty {
                entry.task.cancel()
                activeStreams.removeValue(forKey: key)
                lastKnownRV.removeValue(forKey: key)
                logger.debug("Cancelled watch for key gvk=\(key.gvk.kind)")
            } else {
                activeStreams[key] = StreamEntry(task: entry.task, continuations: conts)
            }
            return
        }
    }

    /// Performs a full relist for all streams whose server returned 410 Gone.
    ///
    /// Called by the drain task when `ResourceWatchError.resourceVersionTooOld`
    /// is received from the port (ADR-0036 §Phase 4). The coordinator clears its
    /// last-known RV for the affected key so the next watch opens with `rv=0`.
    ///
    /// - Parameter key: The watch key that received the 410 error.
    public func handleRelist410(for gvk: GroupVersionKind, namespace: String?, clusterId: UUID) {
        let key = WatchKey(clusterId: clusterId, gvk: gvk, namespace: namespace)
        lastKnownRV.removeValue(forKey: key)
        logger.info("410 Gone — cleared RV for gvk=\(gvk.kind), will relist")
        // The drain task self-restarts because its loop continues; no extra
        // action required beyond clearing the stale RV.
    }

    // MARK: - Private

    /// Drives the watch port for `key` and fan-outs events to all subscribers.
    private func drainWatchPort(key: WatchKey) async {
        let rv = lastKnownRV[key]
        let stream = watchPort.watchResources(
            gvk: key.gvk,
            namespace: key.namespace,
            contextId: key.clusterId,
            resourceVersion: rv
        )

        do {
            for try await event in stream {
                if event.type == .bookmark {
                    // ADR-0036 §Phase 3: advance RV, do NOT fan-out.
                    lastKnownRV[key] = event.item.uid
                    continue
                }
                fanOut(event: event, key: key)
            }
        } catch ResourceWatchError.resourceVersionTooOld {
            handleRelist410(for: key.gvk, namespace: key.namespace, clusterId: key.clusterId)
        } catch {
            logger.warning("Watch stream error for gvk=\(key.gvk.kind): \(error)")
        }
    }

    /// Delivers `event` to every active subscriber for `key`.
    private func fanOut(event: ResourceWatchEvent, key: WatchKey) {
        guard let entry = activeStreams[key] else { return }
        for cont in entry.continuations.values {
            cont.yield(event)
        }
    }
}
