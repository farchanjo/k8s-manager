// Actors/PrometheusQueryActor.swift — metrics_observability bounded context
// DDD role: DomainService (Swift actor)
// ADR ref: ADR-0016 (HTTP client strategy, curated queries)
// ADR ref: ADR-0024 (query budget — 5 queries per refresh cycle)
// ADR ref: ADR-0044 (PromQL injection prevention)

import Dependencies
import Foundation

// MARK: - BudgetExhaustedError

/// Thrown when `PrometheusQueryActor` has exhausted its per-cycle query budget
/// (ADR-0024: maximum 5 queries per refresh cycle).
public struct BudgetExhaustedError: Error, Sendable {
    /// Number of queries that were attempted this cycle before the budget
    /// was exhausted.
    public let queriesAttempted: Int
}

// MARK: - PrometheusQueryActor

/// Actor that executes PromQL instant and range queries against one configured
/// `PrometheusEndpoint`, enforcing a per-cycle query budget (ADR-0024).
///
/// Callers must call `resetBudget()` at the start of each refresh cycle to
/// allow up to `queryBudget` queries. The actor is intentionally scoped to a
/// single endpoint so budget accounting is deterministic.
public actor PrometheusQueryActor {

    // MARK: Public state

    /// The Prometheus endpoint this actor targets.
    public let endpoint: PrometheusEndpoint

    /// Maximum number of queries allowed per refresh cycle (ADR-0024).
    public let queryBudget: Int

    /// Timestamp of the most recent completed query, or `nil` if none has
    /// been executed yet.
    public private(set) var lastQueryAt: Date?

    // MARK: Private state

    /// Number of queries executed in the current refresh cycle.
    private var queriesThisCycle: Int

    @Dependency(\.prometheusQuery) private var queryPort

    // MARK: - Init

    /// Creates a `PrometheusQueryActor` targeting the given endpoint.
    ///
    /// - Parameters:
    ///   - endpoint: The Prometheus endpoint to query.
    ///   - queryBudget: Maximum queries per cycle. Defaults to 5 (ADR-0024).
    public init(endpoint: PrometheusEndpoint, queryBudget: Int = 5) {
        self.endpoint = endpoint
        self.queryBudget = queryBudget
        self.queriesThisCycle = 0
        self.lastQueryAt = nil
    }

    // MARK: - Public API

    /// Executes a PromQL instant query, respecting the per-cycle budget.
    ///
    /// - Parameter query: An instant `PromQuery` (`query.instant == true`).
    /// - Returns: An instant-vector `PromQueryResult`.
    /// - Throws: `BudgetExhaustedError` when the cycle budget is exhausted,
    ///   or `PrometheusQueryError` on transport or decode failure.
    public func runInstant(_ query: PromQuery) async throws -> PromQueryResult {
        try enforceBudget()
        let result = try await queryPort.instantQuery(query, endpoint: endpoint)
        recordQuery()
        return result
    }

    /// Executes a PromQL range query, respecting the per-cycle budget.
    ///
    /// - Parameters:
    ///   - query: A range `PromQuery` (`query.instant == false`).
    ///   - range: The time window and resolution step.
    /// - Returns: A range-matrix `PromQueryResult`.
    /// - Throws: `BudgetExhaustedError` when the cycle budget is exhausted,
    ///   or `PrometheusQueryError` on transport or decode failure.
    public func runRange(
        _ query: PromQuery,
        range: TimeRange
    ) async throws -> PromQueryResult {
        try enforceBudget()
        let rangeQuery = PromQuery.range(expr: query.expr, range: range, labelSelector: query.labelSelector)
        let result = try await queryPort.rangeQuery(rangeQuery, endpoint: endpoint)
        recordQuery()
        return result
    }

    /// Resets the per-cycle query counter. Must be called once at the
    /// beginning of each refresh cycle (ADR-0024).
    public func resetBudget() {
        queriesThisCycle = 0
    }

    /// Returns the number of queries executed in the current cycle.
    public func queriesUsedThisCycle() -> Int {
        queriesThisCycle
    }

    // MARK: - Private

    /// Throws `BudgetExhaustedError` when `queriesThisCycle >= queryBudget`.
    private func enforceBudget() throws {
        guard queriesThisCycle < queryBudget else {
            throw BudgetExhaustedError(queriesAttempted: queriesThisCycle)
        }
    }

    /// Increments the cycle counter and records the query timestamp.
    private func recordQuery() {
        queriesThisCycle += 1
        lastQueryAt = Date()
    }
}
