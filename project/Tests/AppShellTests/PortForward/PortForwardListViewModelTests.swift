// Tests/AppShellTests/PortForward/PortForwardListViewModelTests.swift
// Coverage: PortForwardListViewModel + suggestFreePort()

import XCTest
import Dependencies
@testable import AppShell
import PortForwarding
import SharedKernel

// MARK: - PortForwardListViewModelTests

@MainActor
final class PortForwardListViewModelTests: XCTestCase {

    // MARK: start — loads sessions from repo

    func test_start_loadsSessionsFromRepository() async throws {
        let session = makeSession(local: 8080, remote: 80)
        let stubRepo = StubRepository(sessions: [session])

        try await withDependencies {
            $0.portForwardRepository = stubRepo
        } operation: {
            let sut = PortForwardListViewModel()
            await sut.start(clusterId: ClusterId("test"))
            XCTAssertEqual(sut.sessions.count, 1)
            XCTAssertEqual(sut.sessions.first?.localPort, 8080)
            XCTAssertEqual(sut.sessions.first?.remotePort, 80)
        }
    }

    // MARK: stop — removes row + emits toast

    func test_stop_removesRowAndEmitsToast() async throws {
        let session = makeSession(local: 8081, remote: 9090)
        let stubRepo = StubRepository(sessions: [session])
        let stubLifecycle = StubLifecycle()
        let recordingToast = RecordingToastEmitter()

        try await withDependencies {
            $0.portForwardRepository = stubRepo
            $0.portForwardLifecycle = stubLifecycle
        } operation: {
            let sut = PortForwardListViewModel(toast: recordingToast)
            await sut.start(clusterId: ClusterId("test"))
            let row = try XCTUnwrap(sut.sessions.first)
            await sut.stop(row)

            XCTAssertTrue(sut.sessions.isEmpty)
            let toasts = await recordingToast.emitted
            XCTAssertFalse(toasts.isEmpty)
            XCTAssertEqual(toasts.first?.severity, .info)
        }
    }

    // MARK: openInBrowser — builds correct URL

    func test_openInBrowser_buildsCorrectURL() {
        let session = makeSession(local: 3000, remote: 3000)
        let row = PortForwardRow(
            id: session.id,
            targetName: "my-app",
            targetIcon: "cube.box",
            localPort: 3000,
            remotePort: 3000,
            status: .active,
            bytesIn: 0,
            bytesOut: 0,
            age: "1m"
        )
        XCTAssertEqual(row.urlString, "http://localhost:3000")
    }

    // MARK: copyURL — copies to NSPasteboard

    func test_copyURL_copiesURLToPasteboard() async throws {
        let stubRepo = StubRepository(sessions: [])
        let stubLifecycle = StubLifecycle()
        let recordingToast = RecordingToastEmitter()

        try await withDependencies {
            $0.portForwardRepository = stubRepo
            $0.portForwardLifecycle = stubLifecycle
        } operation: {
            let sut = PortForwardListViewModel(toast: recordingToast)
            let row = PortForwardRow(
                id: UUID(),
                targetName: "nginx",
                targetIcon: "cube.box",
                localPort: 8080,
                remotePort: 80,
                status: .active,
                bytesIn: 0,
                bytesOut: 0,
                age: "2m"
            )
            sut.copyURL(row)
            let pasted = NSPasteboard.general.string(forType: .string)
            XCTAssertEqual(pasted, "http://localhost:8080")
        }
    }

    // MARK: reload — failure path is graceful

    func test_reload_gracefulOnRepositoryFailure() async throws {
        let stubRepo = FailingRepository()

        try await withDependencies {
            $0.portForwardRepository = stubRepo
        } operation: {
            let sut = PortForwardListViewModel()
            await sut.reload()
            XCTAssertNotNil(sut.loadState.error)
            XCTAssertTrue(sut.sessions.isEmpty)
        }
    }

    // MARK: bytesFormatted

    func test_bytesFormatted_displaysHumanReadable() {
        let row = PortForwardRow(
            id: UUID(),
            targetName: "svc",
            targetIcon: "network",
            localPort: 5432,
            remotePort: 5432,
            status: .active,
            bytesIn: 1_258_291,    // ~1.2 MB
            bytesOut: 865_280,     // ~845 KB
            age: "3h"
        )
        let formatted = row.bytesFormatted
        XCTAssertTrue(formatted.contains("↓"))
        XCTAssertTrue(formatted.contains("↑"))
        XCTAssertTrue(formatted.contains("MB") || formatted.contains("KB"))
    }
}

// MARK: - suggestFreePortTests

final class SuggestFreePortTests: XCTestCase {

    func test_suggestFreePort_returnsPortInRange() async {
        let port = await suggestFreePort()
        // Either a port in 8080-8200 range, or 0 (system-assigned fallback).
        XCTAssertTrue((8080...8200).contains(port) || port == 0,
                      "Expected port in 8080-8200 or fallback 0, got \(port)")
    }
}

// MARK: - Test doubles

private struct EmittedToast: Sendable {
    let severity: ToastDomainSeverity
}

private actor RecordingToastEmitter: ToastEmitterPort {
    private(set) var emitted: [EmittedToast] = []

    func emit(
        title: String,
        message: String?,
        severity: ToastDomainSeverity,
        iconSymbolName: String?,
        pinned: Bool,
        action: ToastDomainAction?
    ) async {
        emitted.append(EmittedToast(severity: severity))
    }
}

private func makeSession(local: Int, remote: Int) -> PortForwardSession {
    PortForwardSession(
        kubernetesContextId: UUID(),
        target: .pod(PodTarget(namespace: "default", podName: "test-pod")),
        portMappings: [PortMapping(localPort: local, remotePort: remote)],
        createdAtRFC3339: ISO8601DateFormatter().string(from: Date())
    )
}

private struct StubLifecycle: PortForwardLifecyclePort {
    func start(session: PortForwardSession) async throws -> AsyncStream<PortForwardEvent> {
        AsyncStream { $0.finish() }
    }

    func stop(sessionId: UUID) async {}
    func stopAll() async {}
}

private actor StubRepository: PortForwardRepositoryPort {
    private let stored: [PortForwardSession]

    init(sessions: [PortForwardSession]) {
        stored = sessions
    }

    func save(_ session: PortForwardSession) async throws {}

    func loadAll() async throws -> [PortForwardSession] {
        stored
    }

    func delete(id: UUID) async throws {}
}

private actor FailingRepository: PortForwardRepositoryPort {
    func save(_ session: PortForwardSession) async throws {
        throw PortForwardRepositoryError.saveFailed(detail: "stub")
    }

    func loadAll() async throws -> [PortForwardSession] {
        throw PortForwardRepositoryError.loadFailed(detail: "stub")
    }

    func delete(id: UUID) async throws {
        throw PortForwardRepositoryError.deleteFailed(id: id, detail: "stub")
    }
}
