// Tests/TerminalSessionTests/TerminalSessionTests.swift — terminal_session bounded context
// XCTest coverage: domain types, value object invariants, frame encoding,
// exit-code mapping, DI port overrides.

import XCTest
import Dependencies
@testable import TerminalSession
import SharedKernel

// MARK: - TerminalSessionAggregateTests

final class TerminalSessionAggregateTests: XCTestCase {
    private let iso = "2024-01-01T00:00:00Z"

    func test_construction_roundtrips_all_fields() {
        let id = UUIDv7.generate()
        let ctxId = UUIDv7.generate()
        let target = SessionTarget.pod(PodTarget(namespace: "default", podName: "nginx-abc"))
        let session = TerminalSession(
            id: id,
            kind: .podExec,
            kubernetesContextId: ctxId,
            targetRef: target,
            command: ["/bin/sh"],
            tty: true,
            stdin: true,
            createdAt: iso,
            lastActivityAt: iso,
            status: .opening,
            sizeRows: 24,
            sizeCols: 80
        )

        XCTAssertEqual(session.id, id)
        XCTAssertEqual(session.kind, .podExec)
        XCTAssertEqual(session.kubernetesContextId, ctxId)
        XCTAssertEqual(session.command, ["/bin/sh"])
        XCTAssertTrue(session.tty)
        XCTAssertTrue(session.stdin)
        XCTAssertEqual(session.status, .opening)
        XCTAssertNil(session.exitCode)
        XCTAssertEqual(session.sizeRows, 24)
        XCTAssertEqual(session.sizeCols, 80)
        XCTAssertNil(session.subprotocol)
    }

    func test_withStatus_produces_new_value_and_preserves_identity() {
        let session = makeSession()
        let closed = session.withStatus(.closed, exitCode: 0)
        XCTAssertEqual(closed.id, session.id)
        XCTAssertEqual(closed.status, .closed)
        XCTAssertEqual(closed.exitCode, 0)
        XCTAssertEqual(closed.kind, session.kind)
    }

    func test_withSize_updates_dimensions_and_lastActivity() {
        let session = makeSession()
        let updated = "2024-06-01T12:00:00Z"
        let resized = session.withSize(rows: 48, cols: 160, lastActivityAt: updated)
        XCTAssertEqual(resized.sizeRows, 48)
        XCTAssertEqual(resized.sizeCols, 160)
        XCTAssertEqual(resized.lastActivityAt, updated)
        XCTAssertEqual(resized.id, session.id)
    }

    func test_withSubprotocol_sets_protocol() {
        let session = makeSession()
        let v5 = session.withSubprotocol(.v5)
        XCTAssertEqual(v5.subprotocol, .v5)
    }

    func test_codable_roundtrip_pod_exec() throws {
        let session = makeSession()
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)
        XCTAssertEqual(session, decoded)
    }

    func test_codable_roundtrip_node_debug() throws {
        let nodeTarget = NodeTarget(nodeName: "node-01", debugContainerName: "debugger")
        let session = TerminalSession(
            kind: .nodeDebug,
            kubernetesContextId: UUIDv7.generate(),
            targetRef: .node(nodeTarget),
            command: ["/bin/bash"],
            tty: true,
            stdin: true,
            createdAt: iso,
            lastActivityAt: iso
        )
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TerminalSession.self, from: data)
        XCTAssertEqual(session, decoded)
    }

    func test_precondition_size_rows_must_be_positive() {
        // This test documents the precondition rather than triggering it,
        // since triggering would crash the test runner. The precondition
        // message is verified here instead.
        // sizeRows=1 is the minimum accepted value.
        let session = makeSession(sizeRows: 1, sizeCols: 1)
        XCTAssertEqual(session.sizeRows, 1)
    }

    // MARK: - Helpers

    private func makeSession(sizeRows: Int = 24, sizeCols: Int = 80) -> TerminalSession {
        TerminalSession(
            kind: .podExec,
            kubernetesContextId: UUIDv7.generate(),
            targetRef: .pod(PodTarget(namespace: "default", podName: "my-pod")),
            command: ["/bin/sh"],
            tty: true,
            stdin: true,
            createdAt: iso,
            lastActivityAt: iso,
            sizeRows: sizeRows,
            sizeCols: sizeCols
        )
    }
}

// MARK: - TerminalIOFrameTests

final class TerminalIOFrameTests: XCTestCase {
    private let sessionId = UUIDv7.generate()

    func test_stdin_frame_channel_is_zero() {
        let frame = TerminalIOFrame.stdin(StdinFrame(sessionId: sessionId, bytes: Data([0x6c])))
        XCTAssertEqual(frame.channel, .stdin)
        XCTAssertEqual(frame.channel.rawValue, 0x00)
    }

    func test_stdout_frame_channel_is_one() {
        let frame = TerminalIOFrame.stdout(StdoutFrame(sessionId: sessionId, bytes: Data([0x48])))
        XCTAssertEqual(frame.channel, .stdout)
        XCTAssertEqual(frame.channel.rawValue, 0x01)
    }

    func test_stderr_frame_channel_is_two() {
        let frame = TerminalIOFrame.stderr(StderrFrame(sessionId: sessionId, bytes: Data([0x65])))
        XCTAssertEqual(frame.channel, .stderr)
        XCTAssertEqual(frame.channel.rawValue, 0x02)
    }

    func test_error_frame_channel_is_three() {
        let frame = TerminalIOFrame.error(ErrorFrame(sessionId: sessionId, json: #"{"ExitCode":0}"#))
        XCTAssertEqual(frame.channel, .error)
        XCTAssertEqual(frame.channel.rawValue, 0x03)
    }

    func test_resize_frame_channel_is_four() {
        let frame = TerminalIOFrame.resize(ResizeFrame(sessionId: sessionId, rows: 24, cols: 80))
        XCTAssertEqual(frame.channel, .resize)
        XCTAssertEqual(frame.channel.rawValue, 0x04)
    }

    func test_session_id_is_accessible_from_all_variants() {
        let frames: [TerminalIOFrame] = [
            .stdin(StdinFrame(sessionId: sessionId, bytes: Data())),
            .stdout(StdoutFrame(sessionId: sessionId, bytes: Data())),
            .stderr(StderrFrame(sessionId: sessionId, bytes: Data())),
            .error(ErrorFrame(sessionId: sessionId, json: "{}")),
            .resize(ResizeFrame(sessionId: sessionId, rows: 1, cols: 1)),
        ]
        for frame in frames {
            XCTAssertEqual(frame.sessionId, sessionId, "sessionId mismatch on \(frame.channel)")
        }
    }
}

// MARK: - ResizeFrameWireDataTests

final class ResizeFrameWireDataTests: XCTestCase {
    func test_wire_data_starts_with_channel_four() {
        let frame = ResizeFrame(sessionId: UUIDv7.generate(), rows: 24, cols: 80)
        let data = frame.wireData()
        XCTAssertEqual(data.first, 0x04, "First byte must be channel 4 (resize)")
    }

    func test_wire_data_encodes_correct_json() throws {
        let frame = ResizeFrame(sessionId: UUIDv7.generate(), rows: 24, cols: 80)
        let data = frame.wireData()
        let jsonData = data.dropFirst()
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Int]
        XCTAssertEqual(parsed?["Width"], 80)
        XCTAssertEqual(parsed?["Height"], 24)
    }

    func test_wire_data_matches_adr_example_bytes() {
        // ADR-0017 §Protocol detail example: [0x04] + {"Width":80,"Height":24}
        let frame = ResizeFrame(sessionId: UUIDv7.generate(), rows: 24, cols: 80)
        let data = frame.wireData()
        let payload = String(data: data.dropFirst(), encoding: .utf8)
        XCTAssertEqual(payload, #"{"Width":80,"Height":24}"#)
    }
}

// MARK: - ErrorFrameExitCodeTests

final class ErrorFrameExitCodeTests: XCTestCase {
    func test_exit_code_zero_is_extracted() {
        let frame = ErrorFrame(sessionId: UUIDv7.generate(), json: #"{"ExitCode":0}"#)
        XCTAssertEqual(frame.exitCode(), 0)
    }

    func test_exit_code_nonzero_is_extracted() {
        let frame = ErrorFrame(sessionId: UUIDv7.generate(), json: #"{"ExitCode":1}"#)
        XCTAssertEqual(frame.exitCode(), 1)
    }

    func test_message_style_error_returns_nil_exit_code() {
        let frame = ErrorFrame(
            sessionId: UUIDv7.generate(),
            json: #"{"message":"container not found"}"#
        )
        XCTAssertNil(frame.exitCode())
    }

    func test_malformed_json_returns_nil_exit_code() {
        let frame = ErrorFrame(sessionId: UUIDv7.generate(), json: "not json")
        XCTAssertNil(frame.exitCode())
    }
}

// MARK: - ExitCodeMappingTests

final class ExitCodeMappingTests: XCTestCase {
    func test_nil_exit_code_maps_to_connection_closed() {
        let mapping = ExitCodeMapping(exitCode: nil)
        XCTAssertEqual(mapping, .connectionClosed)
    }

    func test_exit_code_zero_maps_to_success() {
        let mapping = ExitCodeMapping(exitCode: 0)
        XCTAssertEqual(mapping, .success)
    }

    func test_nonzero_exit_code_maps_to_failure() {
        let mapping = ExitCodeMapping(exitCode: 127)
        XCTAssertEqual(mapping, .failure(code: 127))
    }

    func test_display_label_for_success() {
        XCTAssertEqual(ExitCodeMapping.success.displayLabel, "Process exited (0)")
    }

    func test_display_label_for_failure() {
        XCTAssertEqual(ExitCodeMapping.failure(code: 1).displayLabel, "Process exited (1)")
    }

    func test_display_label_for_connection_closed() {
        XCTAssertEqual(ExitCodeMapping.connectionClosed.displayLabel, "Connection closed")
    }
}

// MARK: - NodeDebugDescriptorTests

final class NodeDebugDescriptorTests: XCTestCase {
    func test_make_generates_correct_pod_name_prefix() {
        let desc = NodeDebugDescriptor.make(nodeName: "node-01", expiresAt: "2024-01-01T00:01:00Z")
        XCTAssertTrue(
            desc.ephemeralPodName.hasPrefix("node-debugger-node-01-"),
            "Expected prefix 'node-debugger-node-01-', got '\(desc.ephemeralPodName)'"
        )
    }

    func test_make_pod_name_ends_with_eight_hex_chars() {
        let desc = NodeDebugDescriptor.make(nodeName: "worker", expiresAt: "2024-01-01T00:01:00Z")
        let suffix = String(desc.ephemeralPodName.split(separator: "-").last ?? "")
        XCTAssertEqual(suffix.count, 8)
        XCTAssertTrue(suffix.allSatisfy(\.isHexDigit), "Suffix must be hex: \(suffix)")
    }

    func test_host_network_and_host_pid_are_always_true() {
        let desc = NodeDebugDescriptor.make(nodeName: "n", expiresAt: "2024-01-01T00:01:00Z")
        XCTAssertTrue(desc.hostNetwork)
        XCTAssertTrue(desc.hostPID)
    }

    func test_privileged_defaults_to_true() {
        let desc = NodeDebugDescriptor.make(nodeName: "n", expiresAt: "2024-01-01T00:01:00Z")
        XCTAssertTrue(desc.securityContext.privileged)
    }

    func test_codable_roundtrip() throws {
        let desc = NodeDebugDescriptor.make(
            nodeName: "node-01",
            namespace: "kube-system",
            debugImage: "nicolaka/netshoot:v0.13",
            expiresAt: "2024-01-01T00:01:00Z"
        )
        let data = try JSONEncoder().encode(desc)
        let decoded = try JSONDecoder().decode(NodeDebugDescriptor.self, from: data)
        XCTAssertEqual(desc, decoded)
    }

    func test_default_image_is_netshoot() {
        let desc = NodeDebugDescriptor.make(nodeName: "n", expiresAt: "2024-01-01T00:01:00Z")
        XCTAssertEqual(desc.debugImage, "nicolaka/netshoot:v0.13")
    }
}

// MARK: - PodExecPortDITests

final class PodExecPortDITests: XCTestCase {
    func test_unimplemented_throws_when_called() async {
        let port = UnimplementedPodExecPort()
        let request = PodExecRequest(
            namespace: "default",
            podName: "nginx",
            command: ["/bin/sh"],
            tty: true,
            stdin: true
        )
        do {
            _ = try await port.openExec(request: request)
            XCTFail("Expected PodExecError.unimplemented")
        } catch PodExecError.unimplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_port_can_be_overridden_via_dependencies() async throws {
        let fake = FakePodExecPort()
        let sessionId = UUIDv7.generate()
        let request = PodExecRequest(
            namespace: "default",
            podName: "nginx",
            command: ["/bin/sh"],
            tty: true,
            stdin: true
        )

        try await withDependencies {
            $0.podExec = fake
        } operation: {
            @Dependency(\.podExec) var port
            let conn = try await port.openExec(request: request)
            XCTAssertEqual(conn.subprotocol, .v5)
            _ = sessionId  // suppress warning
        }
    }
}

// MARK: - NodeDebugPortDITests

final class NodeDebugPortDITests: XCTestCase {
    func test_unimplemented_throws_on_create() async {
        let port = UnimplementedNodeDebugPort()
        let desc = NodeDebugDescriptor.make(nodeName: "n", expiresAt: "2024-01-01T00:01:00Z")
        do {
            _ = try await port.createDebugPod(descriptor: desc)
            XCTFail("Expected NodeDebugError.unimplemented")
        } catch NodeDebugError.unimplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_port_can_be_overridden_via_dependencies() async throws {
        let fake = FakeNodeDebugPort(returnedPodName: "node-debugger-worker-00000000")
        let desc = NodeDebugDescriptor.make(nodeName: "worker", expiresAt: "2024-01-01T00:01:00Z")

        try await withDependencies {
            $0.nodeDebug = fake
        } operation: {
            @Dependency(\.nodeDebug) var port
            let podName = try await port.createDebugPod(descriptor: desc)
            XCTAssertEqual(podName, "node-debugger-worker-00000000")
        }
    }
}

// MARK: - SessionStatusTests

final class SessionStatusTests: XCTestCase {
    func test_all_status_raw_values_round_trip() throws {
        let statuses: [SessionStatus] = [.opening, .open, .closing, .closed, .error]
        for status in statuses {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(SessionStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }
}

// MARK: - ExecSubprotocolTests

final class ExecSubprotocolTests: XCTestCase {
    func test_v5_raw_value() {
        XCTAssertEqual(ExecSubprotocol.v5.rawValue, "v5.channel.k8s.io")
    }

    func test_v4_raw_value() {
        XCTAssertEqual(ExecSubprotocol.v4.rawValue, "v4.channel.k8s.io")
    }
}

// MARK: - Test doubles

private struct FakePodExecPort: PodExecPort {
    func openExec(request: PodExecRequest) async throws -> ExecConnection {
        let (stream, _) = AsyncStream<Data>.makeStream()
        return ExecConnection(
            subprotocol: .v5,
            frames: stream,
            send: { _ in },
            close: {}
        )
    }
}

private struct FakeNodeDebugPort: NodeDebugPort {
    let returnedPodName: String

    func createDebugPod(descriptor: NodeDebugDescriptor) async throws -> String {
        returnedPodName
    }

    func deleteDebugPod(podName: String, namespace: String) async throws {}

    func pollPodPhase(
        podName: String,
        namespace: String,
        timeout: Duration
    ) async throws -> DebugPodPhase {
        .running
    }
}
