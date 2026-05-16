// PrometheusQueryActorTests.swift — metrics_observability bounded context
// Coverage: PrometheusQueryActor — budget enforcement (ADR-0024), delegation
//           to PrometheusQueryPort, state tracking.

import Dependencies
import Foundation
import XCTest

@testable import MetricsObservability

// MARK: - Helpers

private func makeEndpoint(auth: AuthStrategy = .none) -> PrometheusEndpoint {
    PrometheusEndpoint(
        id: UUID(),
        kubernetesContextId: UUID(),
        url: "http://prometheus.test:9090",
        discoverySource: .wellKnown,
        authStrategy: auth
    )
}

// MARK: - PrometheusQueryActorTests

final class PrometheusQueryActorTests: XCTestCase {

    // MARK: Budget enforcement

    func test_runInstant_exhaustsBudget_afterMaxQueries() async throws {
        let fake = CountingQueryPort()
        let actor = withDependencies {
            $0.prometheusQuery = fake
        } operation: {
            PrometheusQueryActor(endpoint: makeEndpoint(), queryBudget: 3)
        }

        // First 3 succeed
        for _ in 0..<3 {
            _ = try await actor.runInstant(.instant(expr: "up"))
        }

        // 4th must throw BudgetExhaustedError
        do {
            _ = try await actor.runInstant(.instant(expr: "up"))
            XCTFail("Expected BudgetExhaustedError on 4th call")
        } catch is BudgetExhaustedError {
            // expected
        }
    }

    func test_resetBudget_allowsFurtherQueries() async throws {
        let fake = CountingQueryPort()
        let actor = withDependencies {
            $0.prometheusQuery = fake
        } operation: {
            PrometheusQueryActor(endpoint: makeEndpoint(), queryBudget: 1)
        }

        _ = try await actor.runInstant(.instant(expr: "up"))
        await actor.resetBudget()

        // After reset, another query is allowed
        _ = try await actor.runInstant(.instant(expr: "up"))
        let used = await actor.queriesUsedThisCycle()
        XCTAssertEqual(used, 1)
    }

    func test_queriesUsedThisCycle_incrementsPerQuery() async throws {
        let fake = CountingQueryPort()
        let actor = withDependencies {
            $0.prometheusQuery = fake
        } operation: {
            PrometheusQueryActor(endpoint: makeEndpoint(), queryBudget: 5)
        }

        _ = try await actor.runInstant(.instant(expr: "up"))
        _ = try await actor.runInstant(.instant(expr: "up"))
        let used = await actor.queriesUsedThisCycle()
        XCTAssertEqual(used, 2)
    }

    // MARK: State tracking

    func test_lastQueryAt_isNil_before_any_query() async {
        let actor = PrometheusQueryActor(endpoint: makeEndpoint())
        let ts = await actor.lastQueryAt
        XCTAssertNil(ts)
    }

    func test_lastQueryAt_isSet_after_successful_query() async throws {
        let fake = CountingQueryPort()
        let before = Date()
        let actor = withDependencies {
            $0.prometheusQuery = fake
        } operation: {
            PrometheusQueryActor(endpoint: makeEndpoint(), queryBudget: 5)
        }

        _ = try await actor.runInstant(.instant(expr: "up"))
        let ts = await actor.lastQueryAt
        XCTAssertNotNil(ts)
        XCTAssertGreaterThanOrEqual(ts!, before)
    }

    // MARK: Range delegation

    func test_runRange_delegates_to_queryPort() async throws {
        let fake = CountingQueryPort()
        let range = TimeRange(start: "2024-01-01T00:00:00Z", end: "2024-01-01T01:00:00Z", stepSeconds: 60)
        let actor = withDependencies {
            $0.prometheusQuery = fake
        } operation: {
            PrometheusQueryActor(endpoint: makeEndpoint(), queryBudget: 5)
        }

        let result = try await actor.runRange(.instant(expr: "up"), range: range)
        if case .rangeMatrix = result {
            // ok
        } else {
            XCTFail("Expected .rangeMatrix from CountingQueryPort")
        }
        let used = await actor.queriesUsedThisCycle()
        XCTAssertEqual(used, 1)
    }

    // MARK: Default budget

    func test_default_budget_is_five() async {
        let actor = PrometheusQueryActor(endpoint: makeEndpoint())
        let budget = await actor.queryBudget
        XCTAssertEqual(budget, 5)
    }
}

// MARK: - CountingQueryPort (fake)

/// Fake `PrometheusQueryPort` that returns stub results without touching the network.
private struct CountingQueryPort: PrometheusQueryPort {
    func instantQuery(
        _ query: PromQuery,
        endpoint: PrometheusEndpoint
    ) async throws -> PromQueryResult {
        .instantVector([MetricSample(metric: ["__name__": "up"], timestampUnix: 0, value: 1.0)])
    }

    func rangeQuery(
        _ query: PromQuery,
        endpoint: PrometheusEndpoint
    ) async throws -> PromQueryResult {
        .rangeMatrix([])
    }
}
