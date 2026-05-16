// BudgetsTests.swift — performance budget value object coverage
// Target: SharedKernelTests
// Spec: docs/arch/contexts/_shared/schemas/performance_budgets.cue

import XCTest
@testable import SharedKernel

final class BudgetsTests: XCTestCase {

    /// All eight canonical budget singletons carry the values documented in
    /// `_canonicalBudgets` inside `performance_budgets.cue`.
    func test_canonicalBudgets_matchCueDefaults() {
        XCTAssertEqual(FrameBudget.canonical.targetMs, 16)

        XCTAssertEqual(GlobalAppBudget.canonical.baselineRssMB, 200)
        XCTAssertEqual(GlobalAppBudget.canonical.loadedRssMB, 600)

        XCTAssertEqual(WidgetQueryBudget.canonical.maxPrometheusQueriesPerCycle, 5)
        XCTAssertEqual(WidgetQueryBudget.canonical.maxSimultaneousQueries, 8)
        XCTAssertEqual(WidgetQueryBudget.canonical.refreshIntervalSeconds, 30)
        XCTAssertTrue(WidgetQueryBudget.canonical.coalescingEnabled)

        XCTAssertEqual(WatchStreamBudget.canonical.maxMemoryMB, 10)
        XCTAssertEqual(WatchStreamBudget.canonical.maxConcurrentWatches, 16)
        XCTAssertEqual(WatchStreamBudget.canonical.maxEventLoopThreads, 8)

        XCTAssertEqual(MutationLatencyBudget.canonical.maxContentMB, 1)
        XCTAssertEqual(MutationLatencyBudget.canonical.maxDryRunRequestsPer10Min, 60)

        XCTAssertEqual(LLMTokenBudget.canonical.maxConcurrentToolInvocations, 4)
        XCTAssertEqual(LLMTokenBudget.canonical.maxTokensPerStreamingResponse, 64_000)

        XCTAssertEqual(MCPInvocationBudget.canonical.maxConcurrentSessions, 8)
        XCTAssertEqual(MCPInvocationBudget.canonical.maxBytesBufferedPerSession, 1_048_576)

        XCTAssertEqual(PortForwardLatencyBudget.canonical.maxConcurrentTunnels, 8)
        XCTAssertEqual(PortForwardLatencyBudget.canonical.maxBytesPerSecondPerTunnel, 10_485_760)
    }

    /// Every budget struct round-trips through Codable without data loss.
    func test_budgets_codableRoundTrip() throws {
        let frame = FrameBudget(targetMs: 8)
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(FrameBudget.self, from: data)
        XCTAssertEqual(decoded.targetMs, 8)

        let global = GlobalAppBudget(baselineRssMB: 100, loadedRssMB: 300)
        let gData = try JSONEncoder().encode(global)
        let gDecoded = try JSONDecoder().decode(GlobalAppBudget.self, from: gData)
        XCTAssertEqual(gDecoded, global)

        let portBudget = PortForwardLatencyBudget(
            maxConcurrentTunnels: 4,
            maxBytesPerSecondPerTunnel: 5_242_880
        )
        let pData = try JSONEncoder().encode(portBudget)
        let pDecoded = try JSONDecoder().decode(PortForwardLatencyBudget.self, from: pData)
        XCTAssertEqual(pDecoded, portBudget)
    }

    /// Budget structs satisfy value-type equality: two instances with identical fields are equal.
    func test_budgets_valueSemantics() {
        let a = LLMTokenBudget(maxConcurrentToolInvocations: 2, maxTokensPerStreamingResponse: 32_000)
        let b = LLMTokenBudget(maxConcurrentToolInvocations: 2, maxTokensPerStreamingResponse: 32_000)
        let c = LLMTokenBudget(maxConcurrentToolInvocations: 4, maxTokensPerStreamingResponse: 32_000)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
