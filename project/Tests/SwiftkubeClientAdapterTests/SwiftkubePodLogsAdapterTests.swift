// Tests/SwiftkubeClientAdapterTests/SwiftkubePodLogsAdapterTests.swift
// Coverage: SwiftkubePodLogsAdapter — line parsing, timestamp splitting,
// severity detection, container annotation.

import XCTest
import SharedKernel
@testable import ClusterConnectivity
@testable import SwiftkubeClientAdapter
import ResourceBrowser

// MARK: - SwiftkubePodLogsAdapterTests

/// Unit tests for the pure parsing functions in `SwiftkubePodLogsAdapter`.
/// No network — all tests operate on the in-process parsing helpers.
final class SwiftkubePodLogsAdapterTests: XCTestCase {

    // MARK: Fixture

    private let adapter = SwiftkubePodLogsAdapter(resolver: { _ in
        ClusterParams(
            server: URL(string: "https://127.0.0.1:6443")!,
            auth: .bearerToken(BearerTokenAuth(token: "tok")),
            insecureSkipTLSVerify: true,
            caStrategy: .system
        )
    })

    // MARK: parseLogChunk — splits lines correctly

    func test_buildChunk_splitsMultilineRawString() {
        let raw = "line one\nline two\nline three"
        let chunk = adapter.buildChunk(raw: raw, containerName: "app")
        XCTAssertEqual(chunk.lines.count, 3, "Three newline-delimited lines expected")
        XCTAssertEqual(chunk.lines[0].content, "line one")
        XCTAssertEqual(chunk.lines[1].content, "line two")
        XCTAssertEqual(chunk.lines[2].content, "line three")
    }

    func test_buildChunk_ignoresTrailingNewline() {
        let raw = "alpha\nbeta\n"
        let chunk = adapter.buildChunk(raw: raw, containerName: "svc")
        XCTAssertEqual(chunk.lines.count, 2, "Trailing newline should not produce an empty line")
    }

    // MARK: container annotation preserved

    func test_parseLine_preservesContainerName() {
        let line = adapter.parseLine("hello from app", containerName: "nginx")
        XCTAssertEqual(line.containerName, "nginx")
    }

    // MARK: detectSeverity — ERROR / WARN patterns

    func test_severity_errorKeyword() {
        XCTAssertEqual(adapter.detectSeverity("2026-01-01T00:00:00Z ERROR: disk full"), .error)
    }

    func test_severity_fatalKeyword() {
        XCTAssertEqual(adapter.detectSeverity("FATAL exception in thread main"), .error)
    }

    func test_severity_warnKeyword() {
        XCTAssertEqual(adapter.detectSeverity("WARN  slow query detected 5000ms"), .warning)
    }

    func test_severity_infoKeyword() {
        XCTAssertEqual(adapter.detectSeverity("INFO server started on :8080"), .info)
    }

    func test_severity_debugKeyword() {
        XCTAssertEqual(adapter.detectSeverity("DEBUG cache miss key=abc"), .debug)
    }

    func test_severity_traceKeyword() {
        XCTAssertEqual(adapter.detectSeverity("TRACE entering function parseRequest"), .trace)
    }

    func test_severity_nilWhenNoKeyword() {
        XCTAssertNil(adapter.detectSeverity("the quick brown fox"))
    }

    // MARK: splitTimestamp — RFC 3339 extraction

    func test_splitTimestamp_extractsRFC3339Prefix() {
        let raw = "2026-05-16T14:30:00.123456789Z some log message"
        let (ts, content) = adapter.splitTimestamp(raw)
        XCTAssertNotNil(ts, "Timestamp should be extracted")
        XCTAssertEqual(content, "some log message")
    }

    func test_splitTimestamp_returnsNilWhenNoTimestamp() {
        let raw = "plain log line without timestamp"
        let (ts, content) = adapter.splitTimestamp(raw)
        XCTAssertNil(ts, "No timestamp prefix — should return nil")
        XCTAssertEqual(content, raw)
    }
}
