// WebSocketPortForwardAdapterTests.swift — infrastructure adapter tests
// Coverage: URL builder, channel-index math, construction smoke.
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
