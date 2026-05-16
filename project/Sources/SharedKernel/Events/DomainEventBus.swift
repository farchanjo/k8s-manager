// DomainEventBus.swift — in-process cross-context domain event bus
// Bounded context: shared_kernel
// Decision:        ADR-0040 (cross-context domain event taxonomy)
//
// Swift 6 strict concurrency — actor isolation throughout.
// Combine is prohibited (ADR-0034); subscribers use AsyncStream<EventEnvelope>.
// Payload size is capped at 4 096 bytes (ADR-0040 §constraints).

import Dependencies
import Foundation
import Logging

// MARK: - Error type

/// Errors the ``DomainEventBus`` can surface to callers.
public enum DomainEventBusError: Error, Sendable {
    /// The JSON-encoded payload exceeds the ADR-0040 hard limit of 4 096 bytes.
    case payloadTooLarge(eventType: String, bytes: Int)
}

// MARK: - Port protocol

/// Defines the observable contract of the domain event bus, decoupled from the
/// concrete `actor` implementation so callers depend on the abstraction.
public protocol DomainEventBusPort: Sendable {
    /// Encodes, validates, and fans out `event` to all active subscribers.
    func publish<E: DomainEvent>(_ event: E, sourceContext: String) async throws
    /// Opens a new subscription channel for the given `eventType` name.
    func subscribe(to eventType: String) async -> (UUID, AsyncStream<EventEnvelope>)
    /// Closes and removes a single subscription by `id`.
    func unsubscribe(id: UUID, from eventType: String) async
}

// MARK: - Actor implementation

/// In-process, actor-isolated domain event bus.
///
/// Subscribers receive a dedicated `AsyncStream<EventEnvelope>` that is fed by
/// the bus on every `publish` call. Streams are terminated when ``unsubscribe(id:from:)``
/// is called or when the bus itself is deallocated.
public actor DomainEventBus: DomainEventBusPort {

    // MARK: State

    /// Keyed by event-type name → subscription id → continuation.
    private var subscriptions: [String: [UUID: AsyncStream<EventEnvelope>.Continuation]] = [:]

    private let encoder: JSONEncoder
    private let log: Logger

    // MARK: Initialisation

    /// Creates a new bus. Use ``DomainEventBusKey`` to access the shared instance
    /// via `@Dependency(\.domainEventBus)`.
    public init() {
        encoder = JSONEncoder()
        log = Logger(label: "shared_kernel.DomainEventBus")
    }

    // MARK: Publish

    /// Wraps `event` in an ``EventEnvelope``, enforces the 4 096-byte payload size
    /// guard (ADR-0040), then fans out to every subscriber of that event type.
    public func publish<E: DomainEvent>(_ event: E, sourceContext: String) async throws {
        let eventType = String(describing: E.self)
        let payloadData = try encoder.encode(event.payload)
        guard payloadData.count <= 4_096 else {
            throw DomainEventBusError.payloadTooLarge(eventType: eventType, bytes: payloadData.count)
        }
        let envelope = event.envelope
        log.debug("publish", metadata: ["event": "\(eventType)", "id": "\(envelope.eventId)"])
        guard let continuations = subscriptions[eventType], !continuations.isEmpty else { return }
        for continuation in continuations.values {
            continuation.yield(envelope)
        }
    }

    // MARK: Subscribe

    /// Returns a unique subscription id and an `AsyncStream` that will receive
    /// all future envelopes for `eventType`.
    public func subscribe(to eventType: String) async -> (UUID, AsyncStream<EventEnvelope>) {
        let id = UUID()
        let stream = AsyncStream<EventEnvelope> { [weak self] continuation in
            Task { [weak self] in
                await self?.storeContinuation(continuation, id: id, eventType: eventType)
            }
        }
        return (id, stream)
    }

    // MARK: Unsubscribe

    /// Finishes and removes the subscription identified by `id`.
    public func unsubscribe(id: UUID, from eventType: String) async {
        subscriptions[eventType]?[id]?.finish()
        subscriptions[eventType]?.removeValue(forKey: id)
        if subscriptions[eventType]?.isEmpty == true {
            subscriptions.removeValue(forKey: eventType)
        }
    }

    // MARK: Private helpers

    private func storeContinuation(
        _ continuation: AsyncStream<EventEnvelope>.Continuation,
        id: UUID,
        eventType: String
    ) {
        subscriptions[eventType, default: [:]][id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in await self?.removeContinuation(id: id, eventType: eventType) }
        }
    }

    private func removeContinuation(id: UUID, eventType: String) {
        subscriptions[eventType]?.removeValue(forKey: id)
        if subscriptions[eventType]?.isEmpty == true {
            subscriptions.removeValue(forKey: eventType)
        }
    }
}

// MARK: - Unimplemented sentinel

private struct UnimplementedDomainEventBus: DomainEventBusPort {
    func publish<E: DomainEvent>(_ event: E, sourceContext: String) async throws {
        reportIssue("DomainEventBusPort.publish called on unimplemented instance")
    }
    func subscribe(to eventType: String) async -> (UUID, AsyncStream<EventEnvelope>) {
        reportIssue("DomainEventBusPort.subscribe called on unimplemented instance")
        return (UUID(), AsyncStream { $0.finish() })
    }
    func unsubscribe(id: UUID, from eventType: String) async {
        reportIssue("DomainEventBusPort.unsubscribe called on unimplemented instance")
    }
}

// MARK: - DI registration

/// `DependencyKey` for the shared ``DomainEventBusPort``.
///
/// `liveValue` is a concrete ``DomainEventBus`` actor; the composition root may
/// override it with a pre-constructed instance via `prepareDependencies`.
public enum DomainEventBusKey: DependencyKey {
    public static let liveValue: any DomainEventBusPort = DomainEventBus()
    public static let testValue: any DomainEventBusPort = UnimplementedDomainEventBus()
}

public extension DependencyValues {
    /// The cross-context domain event bus (ADR-0040).
    var domainEventBus: any DomainEventBusPort {
        get { self[DomainEventBusKey.self] }
        set { self[DomainEventBusKey.self] = newValue }
    }
}
