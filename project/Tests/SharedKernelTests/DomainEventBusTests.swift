// DomainEventBusTests.swift — DomainEventBus actor coverage
// Target: SharedKernelTests
// Decision: ADR-0040

import XCTest
@testable import SharedKernel

/// Minimal concrete event used exclusively within this test file.
private struct TestEvent: DomainEvent {
    struct Payload: Sendable, Codable, Hashable {
        let value: String
    }
    let envelope: EventEnvelope
    let payload: Payload

    init(value: String = "ok") {
        envelope = EventEnvelope(
            eventId: UUID().uuidString,
            eventType: "test.TestEvent",
            sourceContext: "test",
            occurredAt: "2026-05-16T00:00:00.000Z"
        )
        payload = Payload(value: value)
    }
}

/// Second event type to verify per-type isolation.
private struct OtherEvent: DomainEvent {
    struct Payload: Sendable, Codable, Hashable {
        let marker: Int
    }
    let envelope: EventEnvelope
    let payload: Payload

    init(marker: Int = 1) {
        envelope = EventEnvelope(
            eventId: UUID().uuidString,
            eventType: "test.OtherEvent",
            sourceContext: "test",
            occurredAt: "2026-05-16T00:00:00.000Z"
        )
        payload = Payload(marker: marker)
    }
}

// MARK: - Helpers

/// Collects the first `count` envelopes from `stream` within `timeout` seconds.
private func collect(
    _ count: Int,
    from stream: AsyncStream<EventEnvelope>,
    timeout: TimeInterval = 2.0
) async -> [EventEnvelope] {
    await withCheckedContinuation { continuation in
        Task {
            var results: [EventEnvelope] = []
            for await envelope in stream {
                results.append(envelope)
                if results.count == count { break }
            }
            continuation.resume(returning: results)
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            continuation.resume(returning: [])
        }
    }
}

// MARK: - Tests

final class DomainEventBusTests: XCTestCase {

    // MARK: 1 — Publish without subscribers emits no error

    func test_publish_withoutSubscribers_noThrow() async throws {
        let bus = DomainEventBus()
        try await bus.publish(TestEvent(), sourceContext: "test")
        // No assertion needed beyond the absence of a thrown error.
    }

    // MARK: 2 — Single subscriber receives the published envelope

    func test_subscribe_thenPublish_receivesEnvelope() async throws {
        let bus = DomainEventBus()
        let (id, stream) = await bus.subscribe(to: "TestEvent")
        let event = TestEvent()

        let collectTask = Task { await collect(1, from: stream) }
        try await bus.publish(event, sourceContext: "test")
        let received = await collectTask.value

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.eventId, event.envelope.eventId)
        await bus.unsubscribe(id: id, from: "TestEvent")
    }

    // MARK: 3 — Two subscribers both receive the same envelope

    func test_twoSubscribers_bothReceive() async throws {
        let bus = DomainEventBus()
        let (id1, stream1) = await bus.subscribe(to: "TestEvent")
        let (id2, stream2) = await bus.subscribe(to: "TestEvent")
        let event = TestEvent()

        let task1 = Task { await collect(1, from: stream1) }
        let task2 = Task { await collect(1, from: stream2) }
        try await bus.publish(event, sourceContext: "test")
        let r1 = await task1.value
        let r2 = await task2.value

        XCTAssertEqual(r1.first?.eventId, event.envelope.eventId)
        XCTAssertEqual(r2.first?.eventId, event.envelope.eventId)
        await bus.unsubscribe(id: id1, from: "TestEvent")
        await bus.unsubscribe(id: id2, from: "TestEvent")
    }

    // MARK: 4 — Unsubscribed listener receives no further events

    func test_unsubscribe_receivesNoMoreEvents() async throws {
        let bus = DomainEventBus()
        let (id, stream) = await bus.subscribe(to: "TestEvent")

        // Drain the first event so the subscriber is active before we unsubscribe.
        let firstTask = Task { await collect(1, from: stream) }
        try await bus.publish(TestEvent(), sourceContext: "test")
        _ = await firstTask.value

        await bus.unsubscribe(id: id, from: "TestEvent")

        // After unsubscribing, publish a second event — stream should not deliver it.
        let secondTask = Task { await collect(1, from: stream, timeout: 0.3) }
        try await bus.publish(TestEvent(), sourceContext: "test")
        let received = await secondTask.value
        XCTAssertTrue(received.isEmpty, "Unsubscribed stream must not receive further events")
    }

    // MARK: 5 — Different event types are isolated from each other

    func test_differentEventTypes_isolated() async throws {
        let bus = DomainEventBus()
        let (idOther, otherStream) = await bus.subscribe(to: "OtherEvent")

        // Publish only a TestEvent; the OtherEvent subscriber should get nothing.
        let collectTask = Task { await collect(1, from: otherStream, timeout: 0.3) }
        try await bus.publish(TestEvent(), sourceContext: "test")
        let received = await collectTask.value

        XCTAssertTrue(received.isEmpty, "OtherEvent stream must not receive TestEvent envelopes")
        await bus.unsubscribe(id: idOther, from: "OtherEvent")
    }

    // MARK: 6 — Payload exactly 4 097 bytes is rejected

    func test_publish_payloadOver4096Bytes_throws() async throws {
        let bus = DomainEventBus()
        // A JSON string value of 4 097 'a' chars is guaranteed to encode > 4 096 bytes.
        let oversized = TestEvent(value: String(repeating: "a", count: 4_097))
        do {
            try await bus.publish(oversized, sourceContext: "test")
            XCTFail("Expected DomainEventBusError.payloadTooLarge to be thrown")
        } catch DomainEventBusError.payloadTooLarge(let eventType, let bytes) {
            XCTAssertEqual(eventType, "TestEvent")
            XCTAssertGreaterThan(bytes, 4_096)
        }
    }

    // MARK: 7 — Payload exactly 4 096 bytes is accepted

    func test_publish_payloadAt4096Bytes_accepted() async throws {
        let bus = DomainEventBus()
        // Build a value whose JSON encoding lands exactly at 4 096 bytes.
        // {"value":"<string>"} — prefix+suffix = 11 bytes, so fill 4085 chars.
        let fittingValue = String(repeating: "a", count: 4_085)
        let event = TestEvent(value: fittingValue)
        // Confirm our assumption about the encoded size.
        let encodedSize = try JSONEncoder().encode(event.payload).count
        XCTAssertLessThanOrEqual(encodedSize, 4_096, "Test fixture must not exceed 4 096 bytes")
        // Must not throw.
        try await bus.publish(event, sourceContext: "test")
    }
}
