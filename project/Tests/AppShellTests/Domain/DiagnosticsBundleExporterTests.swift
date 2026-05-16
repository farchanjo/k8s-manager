// Tests/AppShellTests/Domain/DiagnosticsBundleExporterTests.swift
// Target: AppShellTests
// Coverage: DiagnosticsBundleExporter pipeline + ExportError cases

import XCTest
@testable import AppShell
import Foundation

final class DiagnosticsBundleExporterTests: XCTestCase {

    private var exportDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("k8smanager-test-exports-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: exportDirectory)
        try await super.tearDown()
    }

    // MARK: - Happy path

    func test_export_returnsManifestWithCorrectSampleCount() async throws {
        let sut = makeExporter()
        let samples = makeSamples(count: 10)

        let manifest = try await sut.export(samples: samples, logFiles: ["app.log": "line1\nline2"])

        XCTAssertEqual(manifest.sampleCount, 10)
        XCTAssertTrue(manifest.redactionApplied)
        XCTAssertFalse(manifest.bundleId.isEmpty)
    }

    func test_export_includesRedactedLogFileNames() async throws {
        let sut = makeExporter()
        let samples = makeSamples(count: 1)
        let logs = ["app.log": "hello", "crash.log": "boom"]

        let manifest = try await sut.export(samples: samples, logFiles: logs)

        XCTAssertTrue(manifest.logFilesIncluded.contains("app.log.redacted"))
        XCTAssertTrue(manifest.logFilesIncluded.contains("crash.log.redacted"))
    }

    func test_export_generatedAtIsISO8601() async throws {
        let sut = makeExporter()
        let manifest = try await sut.export(samples: makeSamples(count: 1), logFiles: [:])

        let formatter = ISO8601DateFormatter()
        XCTAssertNotNil(formatter.date(from: manifest.generatedAtRFC3339), "generatedAt must be valid ISO 8601")
    }

    // MARK: - Error cases

    func test_export_throwsNoSamplesAvailableWhenEmpty() async {
        let sut = makeExporter()
        do {
            _ = try await sut.export(samples: [], logFiles: [:])
            XCTFail("Expected ExportError.noSamplesAvailable")
        } catch ExportError.noSamplesAvailable {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_export_throwsRedactionFailedWhenRedactorReturnsNil() async {
        let sut = makeExporter(redactor: FailingRedactor())
        do {
            _ = try await sut.export(samples: makeSamples(count: 1), logFiles: ["app.log": "content"])
            XCTFail("Expected ExportError.redactionFailed")
        } catch ExportError.redactionFailed(_) {
            // expected — fail-safe invariant
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeExporter(redactor: any LogRedactor = PassthroughLogRedactor()) -> DiagnosticsBundleExporter {
        DiagnosticsBundleExporter(exportDirectory: exportDirectory, redactor: redactor)
    }

    private func makeSamples(count: Int) -> [SelfMetricSample] {
        (0..<count).map { i in
            SelfMetricSample(
                timestampRFC3339: "2026-05-15T0\(i % 10):00:00Z",
                cpuUsagePercent: Double(i) * 1.5,
                memoryRSSBytes: 100_000_000,
                memoryPeakRSSBytes: 120_000_000,
                threadCount: 12,
                fileDescriptorCount: 45,
                networkBytesIn: 1_024 * i,
                networkBytesOut: 512 * i,
                activeWatchStreams: 2,
                activeExecSessions: 0,
                activePortForwards: 1,
                activeChatStreams: 0,
                sqliteSizeBytes: 4_096,
                cacheSizeBytes: 8_192,
                actorCount: 5,
                eventLoopGroupCount: 1
            )
        }
    }
}

// MARK: - FailingRedactor test double

private struct FailingRedactor: LogRedactor, Sendable {
    func redact(_ content: String) async -> String? { nil }
}
