// Tests/WebSocketExecAdapterTests/WebSocketExecAdapterTests.swift
// Coverage: frame encode/decode, URL construction, adapter construction.
// No real cluster required — all tests are pure unit tests against the
// frame helper functions and the adapter initialiser.

import XCTest
@testable import WebSocketExecAdapter
import TerminalSession
import Foundation

// MARK: - FrameEncodeTests

final class FrameEncodeTests: XCTestCase {

    // encode(stdin: "ls\n") → starts with 0x00 followed by 'l' 's' '\n'
    func test_encode_stdin_starts_with_channel_zero() {
        let payload = Data("ls\n".utf8)
        let frame = encodeExecFrame(channel: .stdin, payload: payload)

        XCTAssertEqual(frame.first, 0x00, "stdin channel byte must be 0x00")
        XCTAssertEqual(frame.count, 4, "frame must be 1 + 3 bytes")
        XCTAssertEqual([UInt8](frame), [0x00, UInt8(ascii: "l"), UInt8(ascii: "s"), 0x0A])
    }

    func test_encode_stdin_exact_bytes_match_adr_example() {
        // ADR-0017 example: `l` (0x6c) on stdin → [0x00, 0x6c]
        let payload = Data([0x6C])
        let frame = encodeExecFrame(channel: .stdin, payload: payload)

        XCTAssertEqual([UInt8](frame), [0x00, 0x6C])
    }

    func test_encode_stdout_starts_with_channel_one() {
        let frame = encodeExecFrame(channel: .stdout, payload: Data("ok".utf8))
        XCTAssertEqual(frame.first, 0x01)
    }

    func test_encode_stderr_starts_with_channel_two() {
        let frame = encodeExecFrame(channel: .stderr, payload: Data("err".utf8))
        XCTAssertEqual(frame.first, 0x02)
    }

    func test_encode_error_starts_with_channel_three() {
        let frame = encodeExecFrame(channel: .error, payload: Data(#"{"ExitCode":0}"#.utf8))
        XCTAssertEqual(frame.first, 0x03)
    }

    func test_encode_resize_starts_with_channel_four() {
        let json = Data(#"{"Width":80,"Height":24}"#.utf8)
        let frame = encodeExecFrame(channel: .resize, payload: json)
        XCTAssertEqual(frame.first, 0x04)
    }

    func test_encode_empty_payload_produces_single_byte_frame() {
        let frame = encodeExecFrame(channel: .stdin, payload: Data())
        XCTAssertEqual(frame.count, 1)
        XCTAssertEqual(frame.first, 0x00)
    }

    func test_encode_preserves_payload_order() {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let frame = encodeExecFrame(channel: .stdout, payload: payload)
        XCTAssertEqual([UInt8](frame), [0x01, 0xDE, 0xAD, 0xBE, 0xEF])
    }
}

// MARK: - FrameDecodeTests

final class FrameDecodeTests: XCTestCase {

    // decode([0x01, 0x6f, 0x6b]) → stdout "ok"
    func test_decode_stdout_ok() {
        let raw = Data([0x01, 0x6F, 0x6B])
        let result = decodeExecFrame(frame: raw)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.channel, .stdout)
        XCTAssertEqual(String(data: result!.payload, encoding: .utf8), "ok")
    }

    func test_decode_stdin_channel() {
        let raw = Data([0x00]) + Data("ls\n".utf8)
        let result = decodeExecFrame(frame: raw)

        XCTAssertEqual(result?.channel, .stdin)
        XCTAssertEqual(result?.payload, Data("ls\n".utf8))
    }

    func test_decode_stderr_channel() {
        let raw = Data([0x02]) + Data("error".utf8)
        let result = decodeExecFrame(frame: raw)

        XCTAssertEqual(result?.channel, .stderr)
    }

    func test_decode_error_channel() {
        let json = #"{"ExitCode":0}"#
        let raw = Data([0x03]) + Data(json.utf8)
        let result = decodeExecFrame(frame: raw)

        XCTAssertEqual(result?.channel, .error)
        XCTAssertEqual(String(data: result!.payload, encoding: .utf8), json)
    }

    // decode([0x04, ...]) → resize frame
    func test_decode_resize_channel() throws {
        let json = #"{"Width":80,"Height":24}"#
        let raw = Data([0x04]) + Data(json.utf8)
        let result = decodeExecFrame(frame: raw)

        XCTAssertEqual(result?.channel, .resize)
        let parsed = try JSONSerialization.jsonObject(with: result!.payload) as? [String: Int]
        XCTAssertEqual(parsed?["Width"], 80)
        XCTAssertEqual(parsed?["Height"], 24)
    }

    func test_decode_unknown_channel_byte_returns_nil() {
        let raw = Data([0x05, 0xFF])
        let result = decodeExecFrame(frame: raw)
        XCTAssertNil(result, "Channel byte 0x05 is not defined and must return nil")
    }

    func test_decode_empty_data_returns_nil() {
        let result = decodeExecFrame(frame: Data())
        XCTAssertNil(result, "Empty frame has no channel byte and must return nil")
    }

    func test_decode_single_channel_byte_yields_empty_payload() {
        let raw = Data([0x01])
        let result = decodeExecFrame(frame: raw)

        XCTAssertEqual(result?.channel, .stdout)
        XCTAssertEqual(result?.payload, Data())
    }
}

// MARK: - EncodeDecodeRoundtripTests

final class EncodeDecodeRoundtripTests: XCTestCase {

    func test_encode_then_decode_roundtrips_all_channels() {
        let cases: [(ChannelByte, Data)] = [
            (.stdin,  Data("hello".utf8)),
            (.stdout, Data([0xDE, 0xAD])),
            (.stderr, Data("err".utf8)),
            (.error,  Data(#"{"ExitCode":1}"#.utf8)),
            (.resize, Data(#"{"Width":80,"Height":24}"#.utf8)),
        ]

        for (channel, payload) in cases {
            let frame = encodeExecFrame(channel: channel, payload: payload)
            let decoded = decodeExecFrame(frame: frame)

            XCTAssertEqual(decoded?.channel, channel, "channel mismatch for \(channel)")
            XCTAssertEqual(decoded?.payload, payload, "payload mismatch for \(channel)")
        }
    }
}

// MARK: - ResizeFrameWireCompatibilityTests

final class ResizeFrameWireCompatibilityTests: XCTestCase {

    /// Verifies that `ResizeFrame.wireData()` output is decodable by `decodeExecFrame`.
    func test_resize_wire_data_decodable_by_adapter() throws {
        let sessionId = UUID()
        let resizeFrame = ResizeFrame(sessionId: sessionId, rows: 48, cols: 160)
        let wireData = resizeFrame.wireData()

        let decoded = decodeExecFrame(frame: wireData)

        XCTAssertEqual(decoded?.channel, .resize)
        let parsed = try JSONSerialization.jsonObject(with: decoded!.payload) as? [String: Int]
        XCTAssertEqual(parsed?["Width"], 160)
        XCTAssertEqual(parsed?["Height"], 48)
    }
}

// MARK: - AdapterConstructionTests

final class AdapterConstructionTests: XCTestCase {

    func test_adapter_construction_with_mock_url_session() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let base = URL(string: "https://k8s.example.com:6443")!

        // Construction must not throw or trap.
        let adapter = WebSocketExecAdapter(urlSession: session, apiServerBase: base)
        XCTAssertNotNil(adapter)
    }

    func test_adapter_is_sendable() {
        // Compile-time check: WebSocketExecAdapter conforms to Sendable (via actor).
        let _: any Sendable = WebSocketExecAdapter(
            urlSession: .shared,
            apiServerBase: URL(string: "https://k8s.example.com")!
        )
    }

    func test_adapter_conforms_to_pod_exec_port() {
        // Compile-time conformance check.
        let _: any PodExecPort = WebSocketExecAdapter(
            urlSession: .shared,
            apiServerBase: URL(string: "https://k8s.example.com")!
        )
    }
}

// MARK: - MockURLProtocol (stub, no real network)

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let error = URLError(.networkConnectionLost)
        client?.urlProtocol(self, didFailWithError: error)
    }
    override func stopLoading() {}
}
