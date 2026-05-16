// Tests/PortForwardingTests/PortForwardManagerActorTests.swift — port_forwarding bounded context
// Coverage: PortForwardManagerActor lifecycle via fake channel double.
// ADR ref: ADR-0014 (lifecycle state machine, event invariants, cooperative cancellation)

import XCTest
@testable import PortForwarding

// MARK: - PortForwardManagerActorTests

final class PortForwardManagerActorTests: XCTestCase {
    private static let ts = "2026-05-15T12:00:00Z"

    // MARK: - start() emits sessionOpened on success

    func test_start_emitsSessionOpened_whenChannelOpensSuccessfully() async throws {
        let channel = FakePortForwardChannel()
        let actor = PortForwardManagerActor(session: makeSession(), channel: channel)

        try await actor.start()

        let events = await actor.events()
        var iterator = events.makeAsyncIterator()
        let event = await iterator.next()

        guard case .sessionOpened(let payload) = event else {
            XCTFail("Expected .sessionOpened, got \(String(describing: event))")
            return
        }
        XCTAssertFalse(payload.occurredAtRFC3339.isEmpty)
    }

    // MARK: - start() throws and emits sessionFailed when channel open fails

    func test_start_emitsSessionFailed_whenChannelThrows() async throws {
        let channel = FakePortForwardChannel(openShouldFail: true)
        let actor = PortForwardManagerActor(session: makeSession(), channel: channel)

        let events = await actor.events()

        do {
            try await actor.start()
            XCTFail("Expected start() to throw")
        } catch {
            // Expected — channel open failed
        }

        var iterator = events.makeAsyncIterator()
        let event = await iterator.next()
        guard case .sessionFailed(let payload) = event else {
            XCTFail("Expected .sessionFailed after channel open error, got \(String(describing: event))")
            return
        }
        XCTAssertEqual(payload.errorCode, "websocket_upgrade_failed")
    }

    // MARK: - stop() emits sessionClosed and finishes stream

    func test_stop_emitsSessionClosed_andFinishesStream() async throws {
        let channel = FakePortForwardChannel()
        let actor = PortForwardManagerActor(session: makeSession(), channel: channel)

        try await actor.start()
        await actor.stop()

        let events = await actor.events()
        var collected: [PortForwardEvent] = []
        for await event in events {
            collected.append(event)
        }

        let closedEvents = collected.filter {
            if case .sessionClosed = $0 { return true }
            return false
        }
        XCTAssertEqual(closedEvents.count, 1)
    }

    // MARK: - stop() is a no-op when session is not running

    func test_stop_isNoOp_whenSessionNotRunning() async {
        let channel = FakePortForwardChannel()
        let actor = PortForwardManagerActor(session: makeSession(), channel: channel)

        // Never called start(), so session is still .opening — stop() must not crash.
        await actor.stop()

        XCTAssertFalse(channel.closeCalled)
    }

    // MARK: - handleChannelData emits bytesTransferred

    func test_handleChannelData_emitsBytesTransferred_whenRunning() async throws {
        let channel = FakePortForwardChannel()
        let actor = PortForwardManagerActor(session: makeSession(), channel: channel)

        try await actor.start()

        let payload = Data("hello".utf8)
        let frame = PortForwardFrame(portIndex: 0, streamType: .data, payload: payload)
        await actor.handleChannelData(frame)

        let events = await actor.events()
        var iterator = events.makeAsyncIterator()

        // Drain sessionOpened
        _ = await iterator.next()

        let event = await iterator.next()
        guard case .bytesTransferred(let transfer) = event else {
            XCTFail("Expected .bytesTransferred, got \(String(describing: event))")
            return
        }
        XCTAssertEqual(transfer.bytesIn, 5)
        XCTAssertEqual(transfer.bytesOut, 0)
    }

    // MARK: - handleChannelError transitions to error

    func test_handleChannelError_transitionsToError_whenRunning() async throws {
        let channel = FakePortForwardChannel()
        let actor = PortForwardManagerActor(session: makeSession(), channel: channel)

        try await actor.start()

        let errorPayload = Data("pod deleted".utf8)
        let frame = PortForwardFrame(portIndex: 0, streamType: .error, payload: errorPayload)
        await actor.handleChannelError(frame)

        // Give the internally-spawned Task time to run.
        try await Task.sleep(nanoseconds: 10_000_000)

        let events = await actor.events()
        var collected: [PortForwardEvent] = []
        for await event in events {
            collected.append(event)
        }

        let failedEvents = collected.filter {
            if case .sessionFailed = $0 { return true }
            return false
        }
        XCTAssertFalse(failedEvents.isEmpty, "Expected at least one .sessionFailed event")
    }

    // MARK: - Helpers

    private func makeSession() -> PortForwardSession {
        PortForwardSession(
            kubernetesContextId: UUID(),
            target: .pod(PodTarget(namespace: "default", podName: "test-pod")),
            portMappings: [PortMapping(localPort: 8080, remotePort: 80)],
            createdAtRFC3339: Self.ts
        )
    }
}

// MARK: - FakePortForwardChannel

/// Fake ``PortForwardChannelPort`` for unit tests.
///
/// - `openShouldFail`: when `true`, `open(namespace:podName:ports:)` throws
///   ``PortForwardChannelError/upgradeRejected(statusCode:detail:)``.
/// - `closeCalled`: records whether `close()` was invoked, for assertion in stop-is-no-op tests.
private final class FakePortForwardChannel: PortForwardChannelPort, @unchecked Sendable {
    let openShouldFail: Bool
    private(set) var closeCalled = false

    init(openShouldFail: Bool = false) {
        self.openShouldFail = openShouldFail
    }

    func open(namespace: String, podName: String, ports: [Int]) async throws {
        if openShouldFail {
            throw PortForwardChannelError.upgradeRejected(statusCode: 403, detail: "Forbidden")
        }
    }

    func send(_ frame: PortForwardFrame) async throws {}

    func receive() async throws -> PortForwardFrame? { nil }

    func close() async {
        closeCalled = true
    }
}
