// Tests/AppShellTests/PortForwardingViewModelTests.swift
// Coverage: PortForwardingViewModel session load, start, and stop flows.

import XCTest
import Dependencies
@testable import AppShell
import PortForwarding
import SharedKernel

// MARK: - PortForwardingViewModelTests

@MainActor
final class PortForwardingViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = PortForwardingViewModel()
        XCTAssertTrue(sut.sessions.isIdle)
    }

    // MARK: loadSessions

    func test_loadSessions_succeedsWithEmptyListByDefault() async {
        let sut = PortForwardingViewModel()
        await sut.loadSessions()
        XCTAssertEqual(sut.sessions, .success([]))
    }

    // MARK: startNew

    func test_startNew_appendsSessionOnSuccess() async throws {
        let stub = StubLifecycle()
        try await withDependencies {
            $0.portForwardLifecycle = stub
        } operation: {
            let sut = PortForwardingViewModel()
            await sut.loadSessions()
            await sut.startNew(
                target: .pod(PodTarget(namespace: "default", podName: "nginx")),
                mapping: PortMapping(localPort: 8080, remotePort: 80)
            )
            XCTAssertEqual(sut.sessions.value?.count, 1)
            let session = try XCTUnwrap(sut.sessions.value?.first)
            XCTAssertEqual(session.portMappings.first?.localPort, 8080)
            XCTAssertEqual(session.portMappings.first?.remotePort, 80)
        }
    }

    func test_startNew_setsFailureWhenAdapterUnimplemented() async {
        // Default dependency is UnimplementedPortForwardLifecyclePort — throws .unimplemented.
        let sut = PortForwardingViewModel()
        await sut.startNew(
            target: .service(ServiceTarget(namespace: "kube-system", serviceName: "kubernetes")),
            mapping: PortMapping(localPort: 6443, remotePort: 6443)
        )
        XCTAssertNotNil(sut.sessions.error)
        XCTAssertNil(sut.sessions.value)
    }

    // MARK: stopSession

    func test_stopSession_removesSessionFromList() async throws {
        let stub = StubLifecycle()
        try await withDependencies {
            $0.portForwardLifecycle = stub
        } operation: {
            let sut = PortForwardingViewModel()
            await sut.loadSessions()
            await sut.startNew(
                target: .pod(PodTarget(namespace: "default", podName: "redis")),
                mapping: PortMapping(localPort: 6379, remotePort: 6379)
            )
            let sessionId = try XCTUnwrap(sut.sessions.value?.first?.id)
            await sut.stopSession(sessionId)
            XCTAssertEqual(sut.sessions.value?.count, 0)
        }
    }
}

// MARK: - Test doubles

/// Lifecycle stub that always succeeds for `start` and no-ops for `stop`/`stopAll`.
private struct StubLifecycle: PortForwardLifecyclePort {

    func start(session: PortForwardSession) async throws -> AsyncStream<PortForwardEvent> {
        AsyncStream { continuation in continuation.finish() }
    }

    func stop(sessionId: UUID) async {}

    func stopAll() async {}
}
