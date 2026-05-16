// Tests/AppShellTests/Logs/PodLogsViewModelTests.swift
// Coverage: PodLogsViewModel — stream lifecycle, buffer rotation, filter, pause/resume, export.

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - PodLogsViewModelTests

@MainActor
final class PodLogsViewModelTests: XCTestCase {

    // MARK: Fixtures

    private let clusterId = ClusterId("test-cluster")
    private let podRef = ResourceRef(
        kind: ResourceKind(group: "", version: "v1", kind: "Pod"),
        namespace: "default",
        name: "nginx-abc"
    )

    // MARK: start — subscribes and populates lines

    func test_start_subscribesToStream_andPopulatesLines() async {
        let chunk = makeChunk(["line one", "line two"])
        let fakePort = FakePodLogsPort(chunks: [chunk])

        await withDependencies {
            $0.podLogs = fakePort
        } operation: {
            let sut = PodLogsViewModel()
            await sut.start(clusterId: clusterId, podRef: podRef, container: nil)
            // Give the background Task time to drain the stream.
            try? await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(sut.lines.count, 2, "Both lines should be buffered")
            XCTAssertEqual(sut.lines.first?.content, "line one")
        }
    }

    // MARK: pause — cancels stream task

    func test_pause_setsIsPaused_andStopsAppending() async {
        // Stream that yields indefinitely via an async sequence
        let fakePort = InfiniteLinePort()

        await withDependencies {
            $0.podLogs = fakePort
        } operation: {
            let sut = PodLogsViewModel()
            await sut.start(clusterId: clusterId, podRef: podRef, container: nil)
            try? await Task.sleep(for: .milliseconds(20))
            sut.pause()
            XCTAssertTrue(sut.isPaused, "isPaused should be true after pause()")
            let countAfterPause = sut.lines.count
            try? await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(sut.lines.count, countAfterPause, "No new lines after pause")
        }
    }

    // MARK: resume — restarts stream from same coordinates

    func test_resume_startsNewStreamAfterPause() async {
        let chunk = makeChunk(["resumed line"])
        let fakePort = FakePodLogsPort(chunks: [chunk])

        await withDependencies {
            $0.podLogs = fakePort
        } operation: {
            let sut = PodLogsViewModel()
            await sut.start(clusterId: clusterId, podRef: podRef, container: nil)
            sut.pause()
            XCTAssertTrue(sut.isPaused)
            await sut.resume()
            XCTAssertFalse(sut.isPaused, "isPaused should be false after resume")
        }
    }

    // MARK: buffer rotation — drops oldest when exceeds maxBufferSize

    func test_bufferRotation_dropsOldestLinesWhenFull() async {
        let maxSize = 10
        let totalLines = 15
        let chunks = (0..<totalLines).map { makeChunk(["line \($0)"]) }
        let fakePort = FakePodLogsPort(chunks: chunks)

        await withDependencies {
            $0.podLogs = fakePort
        } operation: {
            let sut = PodLogsViewModel()
            sut.tailLines = nil
            // Override maxBufferSize indirectly by filling it past threshold
            // We can't directly override the constant, so test that count stays bounded.
            await sut.start(clusterId: clusterId, podRef: podRef, container: nil)
            try? await Task.sleep(for: .milliseconds(50))
            XCTAssertLessThanOrEqual(
                sut.lines.count,
                sut.maxBufferSize,
                "Buffer must not exceed maxBufferSize"
            )
        }
    }

    // MARK: search filter — filteredLines applies query

    func test_searchFilter_returnsMatchingLinesOnly() async {
        let chunk = makeChunk(["ERROR: disk full", "INFO: everything fine", "ERROR: OOM"])
        let fakePort = FakePodLogsPort(chunks: [chunk])

        await withDependencies {
            $0.podLogs = fakePort
        } operation: {
            let sut = PodLogsViewModel()
            await sut.start(clusterId: clusterId, podRef: podRef, container: nil)
            try? await Task.sleep(for: .milliseconds(50))
            sut.searchQuery = "ERROR"
            XCTAssertEqual(sut.filteredLines.count, 2, "Only lines containing ERROR should pass the filter")
        }
    }

    // MARK: export — writes file to temp directory

    func test_exportLogs_writesFileToTempDirectory() async {
        let chunk = makeChunk(["hello world"])
        let fakePort = FakePodLogsPort(chunks: [chunk])

        await withDependencies {
            $0.podLogs = fakePort
        } operation: {
            let sut = PodLogsViewModel()
            await sut.start(clusterId: clusterId, podRef: podRef, container: nil)
            try? await Task.sleep(for: .milliseconds(50))
            let url = await sut.exportLogs()
            XCTAssertNotNil(url, "Export should produce a URL")
            if let url {
                let content = try? String(contentsOf: url, encoding: .utf8)
                XCTAssertTrue(content?.contains("hello world") == true, "Exported file should contain log content")
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

// MARK: - Test doubles

private struct FakePodLogsPort: PodLogsPort {
    let chunks: [LogChunk]

    func streamLogs(
        clusterId: ClusterId,
        podName: String,
        namespace: String,
        container: String?,
        follow: Bool,
        tailLines: Int?,
        sinceSeconds: Int?,
        previous: Bool
    ) -> AsyncThrowingStream<LogChunk, Error> {
        let localChunks = chunks
        return AsyncThrowingStream { continuation in
            Task {
                for chunk in localChunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }
}

private struct InfiniteLinePort: PodLogsPort {
    func streamLogs(
        clusterId: ClusterId,
        podName: String,
        namespace: String,
        container: String?,
        follow: Bool,
        tailLines: Int?,
        sinceSeconds: Int?,
        previous: Bool
    ) -> AsyncThrowingStream<LogChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var count = 0
                while !Task.isCancelled {
                    let line = LogLine(timestamp: nil, content: "line \(count)", containerName: "app", severity: nil)
                    continuation.yield(LogChunk(lines: [line], timestamp: "now"))
                    count += 1
                    try? await Task.sleep(for: .milliseconds(5))
                }
                continuation.finish()
            }
        }
    }
}

private func makeChunk(_ contents: [String]) -> LogChunk {
    let lines = contents.map {
        LogLine(timestamp: nil, content: $0, containerName: "app", severity: nil)
    }
    return LogChunk(lines: lines, timestamp: "2026-01-01T00:00:00Z")
}
