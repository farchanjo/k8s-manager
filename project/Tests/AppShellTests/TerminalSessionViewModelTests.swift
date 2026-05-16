// Tests/AppShellTests/TerminalSessionViewModelTests.swift
// Coverage: TerminalSessionViewModel session lifecycle + input flows.

import XCTest
import Dependencies
@testable import AppShell
import TerminalSession
import SharedKernel

// MARK: - TerminalSessionViewModelTests

@MainActor
final class TerminalSessionViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = TerminalSessionViewModel()
        XCTAssertTrue(sut.sessions.isIdle)
        XCTAssertTrue(sut.outputBuffer.isEmpty)
        XCTAssertNil(sut.activeSessionId)
    }

    // MARK: loadSessions

    func test_loadSessions_transitionsToSuccessWithEmptyList() async {
        let sut = TerminalSessionViewModel()
        await sut.loadSessions()
        if case .success(let list) = sut.sessions {
            XCTAssertTrue(list.isEmpty)
        } else {
            XCTFail("Expected .success([]), got \(sut.sessions)")
        }
    }

    // MARK: openSession — pod exec failure path

    func test_openSession_podExec_setsFailureWhenAdapterUnimplemented() async {
        await withDependencies {
            $0.podExec = FailingPodExecPort()
        } operation: {
            let sut = TerminalSessionViewModel()
            await sut.loadSessions()
            let target = SessionTarget.pod(PodTarget(namespace: "default", podName: "nginx-abc"))
            await sut.openSession(target: target, kind: .podExec)
            XCTAssertNotNil(sut.sessions.error, "Expected .failure when adapter throws")
        }
    }

    // MARK: sendInput

    func test_sendInput_appendsToOutputBufferWhenSessionActive() async {
        let sut = TerminalSessionViewModel()
        await sut.loadSessions()

        // Simulate an active session by injecting a fake UUID.
        let fakeId = UUIDv7.generate()
        let now = ISO8601DateFormatter().string(from: Date())
        let fakeSession = TerminalSession(
            id: fakeId,
            kind: .podExec,
            kubernetesContextId: UUIDv7.generate(),
            targetRef: .pod(PodTarget(namespace: "default", podName: "test-pod")),
            command: ["/bin/sh"],
            tty: true,
            stdin: true,
            createdAt: now,
            lastActivityAt: now
        )
        sut.sessions = .success([fakeSession])
        sut.activeSessionId = fakeId

        sut.sendInput("ls -la")
        XCTAssertTrue(sut.outputBuffer.contains("ls -la"))
    }

    func test_sendInput_isNoopWhenNoActiveSession() async {
        let sut = TerminalSessionViewModel()
        await sut.loadSessions()
        sut.sendInput("ls")
        XCTAssertTrue(sut.outputBuffer.isEmpty)
    }

    // MARK: closeSession

    func test_closeSession_clearsActiveSessionIdAndAppendsStatusLine() async {
        let sut = TerminalSessionViewModel()
        await sut.loadSessions()

        let fakeId = UUIDv7.generate()
        let now = ISO8601DateFormatter().string(from: Date())
        let fakeSession = TerminalSession(
            id: fakeId,
            kind: .podExec,
            kubernetesContextId: UUIDv7.generate(),
            targetRef: .pod(PodTarget(namespace: "default", podName: "close-test")),
            command: ["/bin/sh"],
            tty: true,
            stdin: true,
            createdAt: now,
            lastActivityAt: now
        )
        sut.sessions = .success([fakeSession])
        sut.activeSessionId = fakeId

        await sut.closeSession(fakeId)

        XCTAssertNil(sut.activeSessionId)
        XCTAssertTrue(sut.outputBuffer.contains("closed"))
        if case .success(let list) = sut.sessions {
            XCTAssertEqual(list.first?.status, .closed)
        } else {
            XCTFail("Expected .success after closeSession")
        }
    }
}

// MARK: - Test doubles

/// Port that always throws `.unimplemented` to exercise the failure path.
private struct FailingPodExecPort: PodExecPort {
    func openExec(request: PodExecRequest) async throws -> ExecConnection {
        throw PodExecError.unimplemented
    }
}
