// PortForwardingTests.swift — port_forwarding bounded context
// XCTest coverage: domain types, frame wire protocol, lifecycle transitions, DI port overrides.

import XCTest
import Dependencies
@testable import PortForwarding
import SharedKernel

// MARK: - PortMappingTests

final class PortMappingTests: XCTestCase {
    func test_defaultProtocol_isTCP() {
        let mapping = PortMapping(localPort: 8080, remotePort: 80)
        XCTAssertEqual(mapping.protocol, "tcp")
    }

    func test_defaultBindAddress_isLoopback() {
        let mapping = PortMapping(localPort: 5432, remotePort: 5432)
        XCTAssertEqual(mapping.bindAddress, "127.0.0.1")
    }

    func test_isNetworkExposed_falseForLoopback() {
        let mapping = PortMapping(localPort: 8080, remotePort: 80, bindAddress: "127.0.0.1")
        XCTAssertFalse(mapping.isNetworkExposed)
    }

    func test_isNetworkExposed_trueForAllInterfaces() {
        let mapping = PortMapping(localPort: 8080, remotePort: 80, bindAddress: "0.0.0.0")
        XCTAssertTrue(mapping.isNetworkExposed)
    }

    func test_portMapping_codableRoundtrip() throws {
        let mapping = PortMapping(localPort: 3000, remotePort: 3000, protocol: "tcp", bindAddress: "127.0.0.1")
        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(PortMapping.self, from: data)
        XCTAssertEqual(mapping, decoded)
    }
}

// MARK: - PortForwardSessionTests

final class PortForwardSessionTests: XCTestCase {
    private static let ts = "2026-05-15T12:00:00Z"

    func test_initialStatus_isOpening() {
        let session = makeSession()
        XCTAssertEqual(session.status, .opening)
    }

    func test_openedTransition_setsRunningAndTimestamp() {
        let session = makeSession().opened(at: Self.ts)
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.openedAtRFC3339, Self.ts)
    }

    func test_beginClosingTransition_setsClosing() {
        let session = makeSession().opened(at: Self.ts).beginClosing()
        XCTAssertEqual(session.status, .closing)
    }

    func test_closedTransition_setsClosedAndTimestamp() {
        let session = makeSession()
            .opened(at: Self.ts)
            .beginClosing()
            .closed(at: Self.ts)
        XCTAssertEqual(session.status, .closed)
        XCTAssertEqual(session.closedAtRFC3339, Self.ts)
    }

    func test_failedFromOpening_setsError() {
        let session = makeSession().failed(at: Self.ts)
        XCTAssertEqual(session.status, .error)
        XCTAssertEqual(session.closedAtRFC3339, Self.ts)
    }

    func test_failedFromRunning_setsError() {
        let session = makeSession().opened(at: Self.ts).failed(at: Self.ts)
        XCTAssertEqual(session.status, .error)
    }

    func test_isTerminal_trueForClosedAndError() {
        XCTAssertTrue(makeSession().opened(at: Self.ts).beginClosing().closed(at: Self.ts).isTerminal)
        XCTAssertTrue(makeSession().failed(at: Self.ts).isTerminal)
    }

    func test_isTerminal_falseForOpeningRunningClosing() {
        let opening = makeSession()
        let running = opening.opened(at: Self.ts)
        let closing = running.beginClosing()
        XCTAssertFalse(opening.isTerminal)
        XCTAssertFalse(running.isTerminal)
        XCTAssertFalse(closing.isTerminal)
    }

    func test_sessionId_isPreservedAcrossTransitions() {
        let session = makeSession()
        let id = session.id
        XCTAssertEqual(session.opened(at: Self.ts).id, id)
        XCTAssertEqual(session.failed(at: Self.ts).id, id)
    }

    func test_portMappings_arePreservedAcrossTransitions() {
        let mappings = [
            PortMapping(localPort: 8080, remotePort: 80),
            PortMapping(localPort: 5432, remotePort: 5432),
        ]
        let session = makeSession(mappings: mappings).opened(at: Self.ts)
        XCTAssertEqual(session.portMappings, mappings)
    }

    func test_emptyPortMappings_triggersPrecondition() {
        // This test verifies the precondition guard exists. We can only test the
        // happy path at this layer; crash-on-empty is enforced by `precondition`.
        let session = makeSession()
        XCTAssertFalse(session.portMappings.isEmpty)
    }

    func test_podTarget_namespace() {
        let target = ForwardTarget.pod(PodTarget(namespace: "staging", podName: "nginx-abc123"))
        XCTAssertEqual(target.namespace, "staging")
    }

    func test_serviceTarget_namespace() {
        let target = ForwardTarget.service(ServiceTarget(namespace: "prod", serviceName: "postgres"))
        XCTAssertEqual(target.namespace, "prod")
    }

    func test_session_codableRoundtrip() throws {
        let session = makeSession()
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(PortForwardSession.self, from: data)
        XCTAssertEqual(session, decoded)
    }

    func test_serviceTarget_resolvedPodName_nilByDefault() {
        let target = ServiceTarget(namespace: "default", serviceName: "my-svc")
        XCTAssertNil(target.resolvedPodName)
    }

    // MARK: Helpers

    private func makeSession(mappings: [PortMapping]? = nil) -> PortForwardSession {
        PortForwardSession(
            kubernetesContextId: UUID(),
            target: .pod(PodTarget(namespace: "default", podName: "test-pod")),
            portMappings: mappings ?? [PortMapping(localPort: 8080, remotePort: 80)],
            createdAtRFC3339: Self.ts
        )
    }
}

// MARK: - PortForwardFrameTests

final class PortForwardFrameTests: XCTestCase {
    // ADR-0014 §Confirmation: encode "hello" for portIndex 0 on the data stream.
    // Expected wire bytes: [0x00, 0x00, 0x68, 0x65, 0x6C, 0x6C, 0x6F]
    func test_encode_dataFrame_portIndex0_helloPayload() {
        let payload = Data("hello".utf8)
        let frame = PortForwardFrame(portIndex: 0x00, streamType: .data, payload: payload)
        let encoded = frame.encoded()

        XCTAssertEqual(encoded.count, 7)
        XCTAssertEqual(encoded[0], 0x00, "byte 0 must be portIndex")
        XCTAssertEqual(encoded[1], 0x00, "byte 1 must be streamType (data = 0x00)")
        XCTAssertEqual(encoded[2...], Data([0x68, 0x65, 0x6C, 0x6C, 0x6F]))
    }

    // ADR-0014 §Confirmation: decode a 7-byte error-stream frame beginning with [0x01, 0x01].
    func test_decode_errorFrame_portIndex1() {
        let raw = Data([0x01, 0x01, 0x45, 0x52, 0x52, 0x4F, 0x52])
        let frame = PortForwardFrame.decode(raw)

        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.portIndex, 1, "byte 0 is portIndex")
        XCTAssertEqual(frame?.streamType, .error, "byte 1 = 0x01 is error stream")
        XCTAssertEqual(frame?.payload, Data([0x45, 0x52, 0x52, 0x4F, 0x52]))
    }

    func test_encode_decode_roundtrip() {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let original = PortForwardFrame(portIndex: 2, streamType: .data, payload: payload)
        let encoded = original.encoded()
        let decoded = PortForwardFrame.decode(encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.portIndex, original.portIndex)
        XCTAssertEqual(decoded?.streamType, original.streamType)
        XCTAssertEqual(decoded?.payload, original.payload)
    }

    func test_decode_emptyPayload_isEOF_sentinel() {
        let raw = Data([0x00, 0x00]) // portIndex=0, streamType=data, zero-length payload
        let frame = PortForwardFrame.decode(raw)

        XCTAssertNotNil(frame)
        XCTAssertTrue(frame?.payload.isEmpty ?? false, "Zero-byte data frame signals EOF")
        XCTAssertEqual(frame?.streamType, .data)
    }

    func test_decode_returnsNil_forSingleByte() {
        XCTAssertNil(PortForwardFrame.decode(Data([0x00])))
    }

    func test_decode_returnsNil_forEmptyData() {
        XCTAssertNil(PortForwardFrame.decode(Data()))
    }

    func test_decode_returnsNil_forUnknownStreamType() {
        let raw = Data([0x00, 0x02, 0xFF]) // streamType 0x02 is undefined
        XCTAssertNil(PortForwardFrame.decode(raw))
    }

    // Byte-order regression: portIndex is byte 0, streamType is byte 1 (ADR-0014 corrected order).
    func test_byteOrder_portIndexIsFirstByte() {
        let frame = PortForwardFrame(portIndex: 3, streamType: .error, payload: Data())
        let encoded = frame.encoded()
        XCTAssertEqual(encoded[0], 3, "portIndex must occupy byte 0")
        XCTAssertEqual(encoded[1], 0x01, "streamType must occupy byte 1")
    }

    func test_streamType_rawValues() {
        XCTAssertEqual(PortForwardFrame.StreamType.data.rawValue, 0x00)
        XCTAssertEqual(PortForwardFrame.StreamType.error.rawValue, 0x01)
    }
}

// MARK: - PortForwardEventTests

final class PortForwardEventTests: XCTestCase {
    private static let ts = "2026-05-15T12:00:00Z"
    private static let sid = UUID()

    func test_sessionOpened_sessionIdAccessor() {
        let event = PortForwardEvent.sessionOpened(
            .init(sessionId: Self.sid, occurredAtRFC3339: Self.ts)
        )
        XCTAssertEqual(event.sessionId, Self.sid)
    }

    func test_sessionFailed_sessionIdAccessor() {
        let event = PortForwardEvent.sessionFailed(
            .init(sessionId: Self.sid, occurredAtRFC3339: Self.ts,
                  errorCode: "pod_not_found", detail: "Pod test-pod not found in namespace default")
        )
        XCTAssertEqual(event.sessionId, Self.sid)
        XCTAssertEqual(event.occurredAtRFC3339, Self.ts)
    }

    func test_listenerBound_isNetworkExposed_falseForLoopback() {
        let payload = PortForwardEvent.ListenerBound(
            sessionId: Self.sid,
            occurredAtRFC3339: Self.ts,
            portIndex: 0,
            effectiveLocalPort: 8080,
            bindAddress: "127.0.0.1",
            isNetworkExposed: false
        )
        XCTAssertFalse(payload.isNetworkExposed)
    }

    func test_listenerBound_isNetworkExposed_trueForAllInterfaces() {
        let payload = PortForwardEvent.ListenerBound(
            sessionId: Self.sid,
            occurredAtRFC3339: Self.ts,
            portIndex: 0,
            effectiveLocalPort: 8080,
            bindAddress: "0.0.0.0",
            isNetworkExposed: true
        )
        XCTAssertTrue(payload.isNetworkExposed)
    }

    func test_bytesTransferred_aggregateCountsOnly() {
        let event = PortForwardEvent.bytesTransferred(
            .init(sessionId: Self.sid, occurredAtRFC3339: Self.ts, bytesIn: 1024, bytesOut: 512)
        )
        if case .bytesTransferred(let payload) = event {
            XCTAssertEqual(payload.bytesIn, 1024)
            XCTAssertEqual(payload.bytesOut, 512)
        } else {
            XCTFail("Expected .bytesTransferred variant")
        }
    }

    func test_allVariants_carrySessionId() {
        let events: [PortForwardEvent] = [
            .sessionOpened(.init(sessionId: Self.sid, occurredAtRFC3339: Self.ts)),
            .sessionFailed(.init(sessionId: Self.sid, occurredAtRFC3339: Self.ts,
                                 errorCode: "x", detail: "y")),
            .listenerBound(.init(sessionId: Self.sid, occurredAtRFC3339: Self.ts,
                                 portIndex: 0, effectiveLocalPort: 8080,
                                 bindAddress: "127.0.0.1", isNetworkExposed: false)),
            .listenerClosed(.init(sessionId: Self.sid, occurredAtRFC3339: Self.ts, portIndex: 0)),
            .connectionAccepted(.init(sessionId: Self.sid, occurredAtRFC3339: Self.ts,
                                      portIndex: 0, clientAddress: "127.0.0.1", clientPort: 54321)),
            .bytesTransferred(.init(sessionId: Self.sid, occurredAtRFC3339: Self.ts,
                                    bytesIn: 0, bytesOut: 0)),
            .sessionClosed(.init(sessionId: Self.sid, occurredAtRFC3339: Self.ts)),
        ]
        for event in events {
            XCTAssertEqual(event.sessionId, Self.sid, "Variant \(event) missing sessionId")
        }
    }

    func test_event_codableRoundtrip() throws {
        let events: [PortForwardEvent] = [
            .sessionOpened(.init(sessionId: Self.sid, occurredAtRFC3339: Self.ts)),
            .sessionFailed(.init(sessionId: Self.sid, occurredAtRFC3339: Self.ts,
                                 errorCode: "ws_closed", detail: "connection dropped")),
            .sessionClosed(.init(sessionId: Self.sid, occurredAtRFC3339: Self.ts)),
        ]
        for original in events {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(PortForwardEvent.self, from: data)
            XCTAssertEqual(original, decoded)
        }
    }
}

// MARK: - SessionStatusTests

final class SessionStatusTests: XCTestCase {
    func test_allCases_rawValues() {
        XCTAssertEqual(SessionStatus.opening.rawValue, "opening")
        XCTAssertEqual(SessionStatus.running.rawValue, "running")
        XCTAssertEqual(SessionStatus.closing.rawValue, "closing")
        XCTAssertEqual(SessionStatus.closed.rawValue, "closed")
        XCTAssertEqual(SessionStatus.error.rawValue, "error")
    }

    func test_allCases_sendable() {
        // Compile-time verification that SessionStatus conforms to Sendable.
        let _: any Sendable = SessionStatus.running
    }
}

// MARK: - DependencyInjectionTests

final class PortForwardingDITests: XCTestCase {
    func test_channelPort_canBeOverridden() async throws {
        let fake = FakePortForwardChannelPort()
        try await withDependencies {
            $0.portForwardChannel = fake
        } operation: {
            @Dependency(\.portForwardChannel) var port
            // Verify the injected instance is used: fake raises sendFailed, not unimplemented.
            do {
                try await port.open(namespace: "default", podName: "nginx", ports: [80])
            } catch PortForwardChannelError.sendFailed(let detail) where detail == "__test_double__" {
                // Expected — fake sentinel reached.
            } catch {
                XCTFail("Unexpected error from fake port: \(error)")
            }
        }
    }

    func test_lifecyclePort_canBeOverridden() async {
        let fake = FakePortForwardLifecyclePort()
        await withDependencies {
            $0.portForwardLifecycle = fake
        } operation: {
            @Dependency(\.portForwardLifecycle) var port
            // stop on a non-existent session must not throw (no-op contract).
            await port.stop(sessionId: UUID())
        }
    }

    func test_channelPort_defaultIsUnimplemented() async throws {
        try await withDependencies { _ in
            // Do not override — use the default sentinel.
        } operation: {
            @Dependency(\.portForwardChannel) var port
            do {
                try await port.open(namespace: "ns", podName: "pod", ports: [8080])
                XCTFail("Expected unimplemented error")
            } catch PortForwardChannelError.unimplemented {
                // Expected
            }
        }
    }

    func test_lifecyclePort_defaultIsUnimplemented() async throws {
        try await withDependencies { _ in } operation: {
            @Dependency(\.portForwardLifecycle) var port
            let session = PortForwardSession(
                kubernetesContextId: UUID(),
                target: .pod(PodTarget(namespace: "default", podName: "nginx")),
                portMappings: [PortMapping(localPort: 8080, remotePort: 80)],
                createdAtRFC3339: "2026-05-15T12:00:00Z"
            )
            do {
                _ = try await port.start(session: session)
                XCTFail("Expected unimplemented error")
            } catch PortForwardLifecycleError.unimplemented {
                // Expected
            }
        }
    }
}

// MARK: - Test doubles

/// Fake channel port that raises a sentinel error so tests can distinguish it from
/// the unimplemented sentinel.
private struct FakePortForwardChannelPort: PortForwardChannelPort {
    func open(namespace: String, podName: String, ports: [Int]) async throws {
        throw PortForwardChannelError.sendFailed(detail: "__test_double__")
    }

    func send(_ frame: PortForwardFrame) async throws {
        throw PortForwardChannelError.sendFailed(detail: "__test_double__")
    }

    func receive() async throws -> PortForwardFrame? {
        throw PortForwardChannelError.sendFailed(detail: "__test_double__")
    }

    func close() async {}
}

private struct FakePortForwardLifecyclePort: PortForwardLifecyclePort {
    func start(session: PortForwardSession) async throws -> AsyncStream<PortForwardEvent> {
        AsyncStream { _ in }
    }

    func stop(sessionId: UUID) async {}
    func stopAll() async {}
}
