// DomainEvent.swift — cross-context domain event protocol and canonical envelope
// Bounded context: shared_kernel
// Spec:           docs/arch/contexts/_shared/schemas/domain_events.cue (#EventEnvelope)
// Decision:       ADR-0040 (cross-context domain event taxonomy)
//
// Swift 6 strict concurrency — all types are value types conforming to Sendable.
// Combine is prohibited (ADR-0034); consumers use AsyncStream<EventEnvelope>.

/// Canonical cross-context domain event envelope.
///
/// Every event emitted on ``DomainEventBusPort`` carries exactly one envelope.
/// Fields mirror `#EventEnvelope` in `domain_events.cue` (ADR-0040).
public struct EventEnvelope: Sendable, Codable, Hashable {
    /// UUIDv7 — time-ordered and globally unique per RFC 9562 §5.7.
    public let eventId: String

    /// Dot-qualified event type name, e.g. `"resource_browser.MutationApplied"`.
    /// Format: `"<sourceContext>.<EventName>"`.
    public let eventType: String

    /// Emitting bounded context name, e.g. `"resource_browser"`.
    public let sourceContext: String

    /// RFC 3339 timestamp with millisecond precision.
    public let occurredAt: String

    /// Optional OpenTelemetry-compatible trace identifier.
    public let traceId: String?

    /// Optional identifier grouping events from the same operator action.
    public let correlationId: String?

    /// Event schema version. Starts at 1; incremented on breaking payload changes.
    public let version: Int

    /// Designated initialiser.
    public init(
        eventId: String,
        eventType: String,
        sourceContext: String,
        occurredAt: String,
        traceId: String? = nil,
        correlationId: String? = nil,
        version: Int = 1
    ) {
        self.eventId = eventId
        self.eventType = eventType
        self.sourceContext = sourceContext
        self.occurredAt = occurredAt
        self.traceId = traceId
        self.correlationId = correlationId
        self.version = version
    }
}

/// Protocol every domain event struct must conform to.
///
/// `Payload` must itself be `Sendable` so the compiler validates zero data-races
/// when crossing actor boundaries (ADR-0040, ADR-0011).
public protocol DomainEvent: Sendable, Codable, Hashable {
    /// The concrete payload type carried by this event.
    associatedtype Payload: Sendable, Codable, Hashable

    /// Canonical envelope; carries tracing and routing metadata.
    var envelope: EventEnvelope { get }

    /// Event-specific data fields mirroring the CUE payload schema.
    var payload: Payload { get }
}
