// DomainEventTests.swift — DomainEvent protocol + EventEnvelope coverage
// Target: SharedKernelTests
// Decision: ADR-0040

import XCTest
@testable import SharedKernel

final class DomainEventTests: XCTestCase {

    // MARK: - EventEnvelope

    /// EventEnvelope round-trips through Codable without data loss.
    func test_eventEnvelope_codableRoundTrip() throws {
        let original = EventEnvelope(
            eventId: "01900000-0000-7000-8000-000000000001",
            eventType: "resource_browser.MutationApplied",
            sourceContext: "resource_browser",
            occurredAt: "2026-05-16T00:00:00.000Z",
            traceId: "trace-abc",
            correlationId: "corr-xyz",
            version: 1
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EventEnvelope.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// EventEnvelope with nil optional fields encodes and decodes cleanly.
    func test_eventEnvelope_nilOptionalFields_roundTrip() throws {
        let original = EventEnvelope(
            eventId: "01900000-0000-7000-8000-000000000002",
            eventType: "cluster_connectivity.ClusterSessionOpened",
            sourceContext: "cluster_connectivity",
            occurredAt: "2026-05-16T00:00:01.000Z"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EventEnvelope.self, from: data)
        XCTAssertNil(decoded.traceId)
        XCTAssertNil(decoded.correlationId)
        XCTAssertEqual(decoded.version, 1)
    }

    /// EventEnvelope participates in Hashable correctly: two equal values share the same hash.
    func test_eventEnvelope_hashableEquality() {
        let a = EventEnvelope(
            eventId: "01900000-0000-7000-8000-000000000003",
            eventType: "local_persistence.AuditEntryAppended",
            sourceContext: "local_persistence",
            occurredAt: "2026-05-16T00:00:02.000Z"
        )
        let b = EventEnvelope(
            eventId: "01900000-0000-7000-8000-000000000003",
            eventType: "local_persistence.AuditEntryAppended",
            sourceContext: "local_persistence",
            occurredAt: "2026-05-16T00:00:02.000Z"
        )
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    /// A concrete DomainEvent struct exposes its envelope and payload through the protocol.
    func test_domainEvent_protocolAccessors() {
        let envelope = EventEnvelope(
            eventId: "01900000-0000-7000-8000-000000000004",
            eventType: "port_forwarding.PortForwardEstablished",
            sourceContext: "port_forwarding",
            occurredAt: "2026-05-16T00:00:03.000Z"
        )
        let payload = PortForwardEstablished.Payload(
            clusterId: "cluster-1",
            namespace: "default",
            podName: "nginx-abc",
            localPort: 8080,
            remotePort: 80
        )
        let event = PortForwardEstablished(envelope: envelope, payload: payload)

        // Access through existential to exercise the protocol surface.
        func assertSourceContext<E: DomainEvent>(_ e: E, expected: String) {
            XCTAssertEqual(e.envelope.sourceContext, expected)
        }
        assertSourceContext(event, expected: "port_forwarding")
        XCTAssertEqual(event.payload.localPort, 8080)
    }
}
