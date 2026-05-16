// Tests/AppShellTests/Terminal/PodExecViewModelTests.swift
// Coverage: PodExecViewModel connection lifecycle + ring-buffer + input forwarding.

import XCTest
import Dependencies
@testable import AppShell
import TerminalSession
import SharedKernel

// MARK: - PodExecViewModelTests

@MainActor
final class PodExecViewModelTests: XCTestCase {

    // MARK: - connect() passes correct params to execPort

    func test_connect_callsOpenExecWithCorrectParams() async throws {
        let spy = SpyPodExecPort()
        await withDependencies {
            $0.podExec = spy
        } operation: {
            let sut = PodExecViewModel()
            let podKind = ResourceKind(group: "", version: "v1", kind: "Pod")
            let ref = ResourceRef(kind: podKind, namespace: "staging", name: "api-pod")
            await sut.connect(clusterId: ClusterId(rawValue: "test-cluster"), podRef: ref, container: "main")
            XCTAssertEqual(spy.lastRequest?.namespace, "staging")
            XCTAssertEqual(spy.lastRequest?.podName, "api-pod")
            XCTAssertEqual(spy.lastRequest?.containerName, "main")
            XCTAssertEqual(spy.lastRequest?.command, ["/bin/sh"])
            XCTAssertTrue(spy.lastRequest?.tty == true)
        }
    }

    // MARK: - connect() transitions state to connected

    func test_connect_setsConnectionStateConnectedOnSuccess() async {
        await withDependencies {
            $0.podExec = StubSuccessfulExecPort()
        } operation: {
            let sut = PodExecViewModel()
            let podKind = ResourceKind(group: "", version: "v1", kind: "Pod")
            let ref = ResourceRef(kind: podKind, namespace: "default", name: "test-pod")
            await sut.connect(
                clusterId: ClusterId(rawValue: "cluster-1"),
                podRef: ref,
                container: nil
            )
            XCTAssertEqual(sut.connectionState, .connected)
        }
    }

    // MARK: - connect() sets failed state on exec error

    func test_connect_setsFailedStateOnExecError() async {
        await withDependencies {
            $0.podExec = FailingPodExecPort()
        } operation: {
            let sut = PodExecViewModel()
            let podKind = ResourceKind(group: "", version: "v1", kind: "Pod")
            let ref = ResourceRef(kind: podKind, namespace: "default", name: "bad-pod")
            await sut.connect(
                clusterId: ClusterId(rawValue: "cluster-1"),
                podRef: ref,
                container: nil
            )
            if case .failed = sut.connectionState {
                // expected
            } else {
                XCTFail("Expected .failed, got \(sut.connectionState)")
            }
        }
    }

    // MARK: - Ring buffer truncates at 64 KB

    func test_outputBuffer_truncatesAt64KB() async {
        await withDependencies {
            $0.podExec = StubSuccessfulExecPort()
        } operation: {
            let sut = PodExecViewModel()
            // Inject 65 KB via reflection-free public API (simulate via model directly)
            let chunk = String(repeating: "A", count: 1_024)  // 1 KB
            for _ in 0..<66 { sut.outputBuffer += chunk }  // 66 KB
            // Trigger ring-buffer trim inline by appending one more byte
            sut.outputBuffer += "X"
            // Buffer must be ≤ 64 KB - 16 KB + 1 byte = 48 KB + trailing "X" + ~remainder
            XCTAssertLessThanOrEqual(
                sut.outputBuffer.utf8.count,
                64 * 1_024,
                "Output buffer must not exceed 64 KB"
            )
        }
    }

    // MARK: - disconnect() closes connection cleanly

    func test_disconnect_setsDisconnectedState() async {
        let port = StubSuccessfulExecPort()
        await withDependencies {
            $0.podExec = port
        } operation: {
            let sut = PodExecViewModel()
            let podKind = ResourceKind(group: "", version: "v1", kind: "Pod")
            let ref = ResourceRef(kind: podKind, namespace: "default", name: "pod-x")
            await sut.connect(
                clusterId: ClusterId(rawValue: "cluster-1"),
                podRef: ref,
                container: nil
            )
            await sut.disconnect()
            if case .disconnected = sut.connectionState {
                // expected
            } else {
                XCTFail("Expected .disconnected, got \(sut.connectionState)")
            }
        }
    }

    // MARK: - container switch reconnects

    func test_switchContainer_resetsBufferAndReconnects() async {
        let port = SpyPodExecPort()
        await withDependencies {
            $0.podExec = port
        } operation: {
            let sut = PodExecViewModel()
            let podKind = ResourceKind(group: "", version: "v1", kind: "Pod")
            let ref = ResourceRef(kind: podKind, namespace: "default", name: "multi-pod")
            sut.outputBuffer = "old output"
            await sut.connect(
                clusterId: ClusterId(rawValue: "cluster-1"),
                podRef: ref,
                container: "sidecar"
            )
            await sut.switchContainer("main")
            XCTAssertEqual(sut.selectedContainer, "main")
            XCTAssertTrue(sut.outputBuffer.isEmpty, "Buffer must be cleared on container switch")
            XCTAssertEqual(port.lastRequest?.containerName, "main")
        }
    }
}

// MARK: - Test doubles

/// Spy that records the most recent `PodExecRequest` and returns a no-op connection.
private final class SpyPodExecPort: PodExecPort, @unchecked Sendable {
    var lastRequest: PodExecRequest?

    func openExec(request: PodExecRequest) async throws -> ExecConnection {
        lastRequest = request
        let (stream, cont) = AsyncStream<Data>.makeStream()
        cont.finish()
        return ExecConnection(
            subprotocol: .v5,
            frames: stream,
            send: { _ in },
            close: {}
        )
    }
}

/// Returns a no-op connection immediately without recording the request.
private struct StubSuccessfulExecPort: PodExecPort {
    func openExec(request: PodExecRequest) async throws -> ExecConnection {
        let (stream, cont) = AsyncStream<Data>.makeStream()
        cont.finish()
        return ExecConnection(
            subprotocol: .v5,
            frames: stream,
            send: { _ in },
            close: {}
        )
    }
}

/// Always throws `PodExecError.handshakeFailed`.
private struct FailingPodExecPort: PodExecPort {
    func openExec(request: PodExecRequest) async throws -> ExecConnection {
        throw PodExecError.handshakeFailed(detail: "stub failure")
    }
}
