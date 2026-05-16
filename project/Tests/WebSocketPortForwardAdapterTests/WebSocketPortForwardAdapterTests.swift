// WebSocketPortForwardAdapterTests.swift — infrastructure adapter tests
// Coverage: URL builder, channel-index math, frame layout (ADR-0014), construction smoke.
// XCTest / Swift 6 strict concurrency.

import XCTest
import Foundation
import PortForwarding
@testable import WebSocketPortForwardAdapter

// MARK: - URLBuilderTests

final class URLBuilderTests: XCTestCase {

    private let apiServer = URL(string: "https://192.168.1.1:6443")!

    func test_portForwardURL_schemeIsWss() {
        let url = URLBuilder.portForwardURL(
            baseURL: apiServer,
            namespace: "default",
            podName: "nginx",
            ports: [8080]
        )
        XCTAssertEqual(url?.scheme, "wss")
    }

    func test_portForwardURL_pathContainsNamespaceAndPod() {
        let url = URLBuilder.portForwardURL(
            baseURL: apiServer,
            namespace: "staging",
            podName: "my-pod",
            ports: [80]
        )
        XCTAssertTrue(
            url?.path.hasSuffix("/namespaces/staging/pods/my-pod/portforward") == true,
            "Expected portforward path, got: \(url?.path ?? "nil")"
        )
    }

    func test_portForwardURL_singlePort_queryString() {
        let url = URLBuilder.portForwardURL(
            baseURL: apiServer,
            namespace: "default",
            podName: "nginx",
            ports: [8080]
        )
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "ports")
        XCTAssertEqual(items[0].value, "8080")
    }

    func test_portForwardURL_multiplePorts_queryString() {
        let url = URLBuilder.portForwardURL(
            baseURL: apiServer,
            namespace: "default",
            podName: "nginx",
            ports: [8080, 5432, 9090]
        )
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map { $0.value }, ["8080", "5432", "9090"])
    }

    func test_portForwardURL_emptyPorts_returnsNil() {
        let url = URLBuilder.portForwardURL(
            baseURL: apiServer,
            namespace: "default",
            podName: "nginx",
            ports: []
        )
        XCTAssertNil(url)
    }

    func test_portForwardURL_httpsBaseSchemeOverriddenToWss() {
        let httpBase = URL(string: "http://10.0.0.1:6443")!
        let url = URLBuilder.portForwardURL(
            baseURL: httpBase,
            namespace: "ns",
            podName: "pod",
            ports: [80]
        )
        XCTAssertEqual(url?.scheme, "wss")
    }
}

// MARK: - PortForwardChannelIndexTests

final class PortForwardChannelIndexTests: XCTestCase {

    // 1 port → 2 channels (data=0, error=1)
    func test_onePort_twoChannels() {
        XCTAssertEqual(PortForwardChannelIndex.channelCount(forPortCount: 1), 2)
        XCTAssertEqual(PortForwardChannelIndex.data(forPortAt: 0), 0)
        XCTAssertEqual(PortForwardChannelIndex.error(forPortAt: 0), 1)
    }

    // 2 ports → 4 channels
    func test_twoPorts_fourChannels() {
        XCTAssertEqual(PortForwardChannelIndex.channelCount(forPortCount: 2), 4)
        XCTAssertEqual(PortForwardChannelIndex.data(forPortAt: 1), 2)
        XCTAssertEqual(PortForwardChannelIndex.error(forPortAt: 1), 3)
    }

    // 3 ports → 6 channels
    func test_threePorts_sixChannels() {
        XCTAssertEqual(PortForwardChannelIndex.channelCount(forPortCount: 3), 6)
        XCTAssertEqual(PortForwardChannelIndex.data(forPortAt: 2), 4)
        XCTAssertEqual(PortForwardChannelIndex.error(forPortAt: 2), 5)
    }

    func test_errorChannelIsAlwaysDataChannelPlusOne() {
        for i in 0..<10 {
            XCTAssertEqual(
                PortForwardChannelIndex.error(forPortAt: i),
                PortForwardChannelIndex.data(forPortAt: i) + 1,
                "Port \(i): error channel must be data channel + 1"
            )
        }
    }

    func test_dataChannelIsAlwaysEven() {
        for i in 0..<10 {
            XCTAssertTrue(
                PortForwardChannelIndex.data(forPortAt: i) % 2 == 0,
                "Port \(i): data channel must be even"
            )
        }
    }

    func test_errorChannelIsAlwaysOdd() {
        for i in 0..<10 {
            XCTAssertTrue(
                PortForwardChannelIndex.error(forPortAt: i) % 2 == 1,
                "Port \(i): error channel must be odd"
            )
        }
    }
}

// MARK: - PortForwardFrameLayoutTests (ADR-0014 §Confirmation)

/// Byte-exact wire-layout tests mandated by ADR-0014 §Confirmation.
///
/// These tests protect against regressions to the previously incorrect byte order
/// (channel-first instead of portIndex-first). The corrected layout is:
///   byte 0 = portIndex, byte 1 = streamType, bytes 2… = payload.
final class PortForwardFrameLayoutTests: XCTestCase {

    // ADR-0014 §Confirmation: encode "hello" (5 bytes) for portIndex 0, data stream.
    // Expected wire bytes: [0x00, 0x00, 0x68, 0x65, 0x6C, 0x6C, 0x6F]
    func test_encode_portIndex0_data_hello_matchesADRVector() {
        let frame = PortForwardFrame(
            portIndex: 0,
            streamType: .data,
            payload: Data("hello".utf8)
        )
        let wire = frame.encoded()
        XCTAssertEqual([UInt8](wire), [0x00, 0x00, 0x68, 0x65, 0x6C, 0x6C, 0x6F],
                       "Wire bytes must match ADR-0014 §Confirmation vector exactly")
    }

    // ADR-0014 §Confirmation: decode [0x01, 0x01, …] → portIndex 1, streamType error.
    func test_decode_portIndex1_error_stream() {
        let wire = Data([0x01, 0x01, 0x62, 0x61, 0x64]) // portIndex=1, error, "bad"
        let frame = PortForwardFrame.decode(wire)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.portIndex, 1)
        XCTAssertEqual(frame?.streamType, .error)
        XCTAssertEqual(String(data: frame?.payload ?? Data(), encoding: .utf8), "bad")
    }

    func test_encode_decode_roundtrip_portIndex2_data() {
        let original = PortForwardFrame(
            portIndex: 2,
            streamType: .data,
            payload: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )
        let decoded = PortForwardFrame.decode(original.encoded())
        XCTAssertEqual(decoded?.portIndex, original.portIndex)
        XCTAssertEqual(decoded?.streamType, original.streamType)
        XCTAssertEqual(decoded?.payload, original.payload)
    }

    func test_empty_payload_data_frame_signals_eof() {
        // Zero-byte payload on data stream = graceful half-close (ADR-0014 §Wire protocol)
        let frame = PortForwardFrame(portIndex: 0, streamType: .data, payload: Data())
        let wire = frame.encoded()
        XCTAssertEqual(wire.count, 2, "Header only, no payload bytes")
        XCTAssertEqual([UInt8](wire), [0x00, 0x00])
    }

    func test_decode_too_short_returns_nil() {
        XCTAssertNil(PortForwardFrame.decode(Data()), "Empty data must return nil")
        XCTAssertNil(PortForwardFrame.decode(Data([0x00])), "Single byte must return nil")
    }

    func test_decode_unknown_streamType_returns_nil() {
        // Byte 1 = 0xFF is not a recognised streamType.
        let wire = Data([0x00, 0xFF, 0x01])
        XCTAssertNil(PortForwardFrame.decode(wire))
    }

    func test_port_index_byte_is_first_byte_not_second() {
        // Regression guard: byte 0 must be portIndex, not streamType.
        // portIndex=3, streamType=data → first byte MUST be 0x03 (portIndex 3).
        let frame = PortForwardFrame(portIndex: 3, streamType: .data, payload: Data())
        let wire = frame.encoded()
        XCTAssertEqual(wire[wire.startIndex], 0x03, "byte 0 must be portIndex")
        XCTAssertEqual(wire[wire.startIndex.advanced(by: 1)], 0x00, "byte 1 must be streamType (data=0x00)")
    }
}

// MARK: - WebSocketPortForwardAdapterConstructionTests

final class WebSocketPortForwardAdapterConstructionTests: XCTestCase {

    func test_construction_doesNotThrow() {
        let session = URLSession(configuration: .ephemeral)
        let base = URL(string: "https://localhost:6443")!
        // Construction must complete without side effects (no network call).
        let adapter = WebSocketPortForwardAdapter(urlSession: session, baseURL: base)
        XCTAssertNotNil(adapter)
    }

    func test_send_beforeOpen_throwsConnectionClosed() async {
        let session = URLSession(configuration: .ephemeral)
        let base = URL(string: "https://localhost:6443")!
        let adapter = WebSocketPortForwardAdapter(urlSession: session, baseURL: base)
        do {
            let frame = makeDataFrame()
            try await adapter.send(frame)
            XCTFail("Expected connectionClosed error")
        } catch PortForwardChannelError.connectionClosed {
            // Expected: wsTask is nil before open.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_receive_beforeOpen_throwsConnectionClosed() async {
        let session = URLSession(configuration: .ephemeral)
        let base = URL(string: "https://localhost:6443")!
        let adapter = WebSocketPortForwardAdapter(urlSession: session, baseURL: base)
        do {
            _ = try await adapter.receive()
            XCTFail("Expected connectionClosed error")
        } catch PortForwardChannelError.connectionClosed {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_close_beforeOpen_isNoOp() async {
        let session = URLSession(configuration: .ephemeral)
        let base = URL(string: "https://localhost:6443")!
        let adapter = WebSocketPortForwardAdapter(urlSession: session, baseURL: base)
        // Must complete without crash or error.
        await adapter.close()
    }

    // MARK: - Helpers

    private func makeDataFrame() -> PortForwardFrame {
        PortForwardFrame(portIndex: 0, streamType: .data, payload: Data("ping".utf8))
    }
}
