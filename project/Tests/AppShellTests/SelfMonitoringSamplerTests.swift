// Tests/AppShellTests/SelfMonitoringSamplerTests.swift
// Target: AppShellTests
// Coverage: SelfMonitoringSampler construction, sample values, lifecycle

import XCTest
@testable import AppShell

// MARK: - SelfMonitoringSamplerTests

final class SelfMonitoringSamplerTests: XCTestCase {

    // MARK: - Construction smoke

    func test_init_doesNotStartSampling() async {
        let aggregate = makeAggregate()
        _ = SelfMonitoringSampler(aggregate: aggregate, intervalSeconds: 60)
        // No samples should be present — sampler must not start implicitly.
        let samples = await aggregate.currentSamples
        XCTAssertTrue(samples.isEmpty)
    }

    // MARK: - One sample produces non-zero values

    func test_oneSample_producesNonSentinelMemory() async throws {
        let aggregate = makeAggregate()
        let sut = SelfMonitoringSampler(aggregate: aggregate, intervalSeconds: 0.01)

        await sut.start()
        try await waitForSample(in: aggregate, minCount: 1)
        await sut.stop()

        let samples = await aggregate.currentSamples
        XCTAssertFalse(samples.isEmpty, "Expected at least one sample")

        let first = try XCTUnwrap(samples.first)
        // RSS should be > 0 for any live process.
        XCTAssertGreaterThan(first.memoryRSSBytes, 0, "RSS must be > 0")
    }

    func test_oneSample_producesNonNegativeThreadCount() async throws {
        let aggregate = makeAggregate()
        let sut = SelfMonitoringSampler(aggregate: aggregate, intervalSeconds: 0.01)

        await sut.start()
        try await waitForSample(in: aggregate, minCount: 1)
        await sut.stop()

        let samples = await aggregate.currentSamples
        let first = try XCTUnwrap(samples.first)
        XCTAssertGreaterThan(first.threadCount, 0, "Thread count must be > 0")
    }

    // MARK: - Start / stop lifecycle

    func test_startStop_doesNotCrash() async {
        let aggregate = makeAggregate()
        let sut = SelfMonitoringSampler(aggregate: aggregate, intervalSeconds: 0.01)
        await sut.start()
        await sut.stop()
        // No assertion needed — absence of crash or Task leak is the contract.
    }

    func test_stop_haltsSampling() async throws {
        let aggregate = makeAggregate()
        let sut = SelfMonitoringSampler(aggregate: aggregate, intervalSeconds: 0.01)

        await sut.start()
        try await waitForSample(in: aggregate, minCount: 1)
        await sut.stop()

        let countAfterStop = await aggregate.currentSamples.count
        // Sleep longer than one interval and verify the count does not grow.
        try await Task.sleep(nanoseconds: 80_000_000)  // 80 ms > 10 ms interval
        let countLater = await aggregate.currentSamples.count
        XCTAssertEqual(countAfterStop, countLater, "Sampler must not append after stop()")
    }

    // MARK: - Sample interval respected

    func test_intervalRespected_producesTwoSamplesWithinWindow() async throws {
        let aggregate = makeAggregate()
        let sut = SelfMonitoringSampler(aggregate: aggregate, intervalSeconds: 0.02)

        await sut.start()
        try await waitForSample(in: aggregate, minCount: 2, timeoutSecs: 3)
        await sut.stop()

        let count = await aggregate.currentSamples.count
        XCTAssertGreaterThanOrEqual(count, 2, "Expected ≥2 samples within window")
    }

    // MARK: - Helpers

    private func makeAggregate() -> SelfMonitoringStateAggregate {
        SelfMonitoringStateAggregate(
            initial: SelfMonitoringState(id: UUID().uuidString)
        )
    }

    /// Polls the aggregate until `minCount` samples exist or timeout elapses.
    private func waitForSample(
        in aggregate: SelfMonitoringStateAggregate,
        minCount: Int,
        timeoutSecs: Double = 2.0
    ) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSecs)
        while Date.now < deadline {
            let count = await aggregate.currentSamples.count
            if count >= minCount { return }
            try await Task.sleep(nanoseconds: 10_000_000)  // 10 ms poll
        }
        let count = await aggregate.currentSamples.count
        XCTAssertGreaterThanOrEqual(count, minCount, "Timed out waiting for \(minCount) sample(s)")
    }
}
