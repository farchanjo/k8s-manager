// Domain/WidgetBudget.swift — analytics_dashboard bounded context
// DDD role: ValueObject (query budget invariant)
// Spec:      docs/arch/contexts/analytics_dashboard/schemas/widget_budget.cue
// ADR ref:   ADR-0024 §Query budget invariant
//
// Swift 6 strict concurrency — all types are value types conforming to Sendable.

import Foundation

// MARK: - WidgetBudget

/// Enforces the query budget invariants declared in ADR-0024.
///
/// Every `Dashboard` carries a `WidgetBudget` and `WidgetQueryDispatchService`
/// validates all constraints before dispatching queries for a refresh cycle.
///
/// Invariants:
/// - `maxPrometheusQueriesPerCycle` ∈ [1, 5].
/// - `maxSimultaneousQueries` ∈ [1, 8].
/// - `refreshIntervalSeconds` ∈ [5, 60].
/// - `coalescingEnabled` is always `true`; `false` is a spec error.
///
/// Mirrors `#WidgetBudget` in `widget_budget.cue`.
public struct WidgetBudget: Sendable, Codable, Hashable {
    /// Maximum number of distinct Prometheus range queries per refresh cycle.
    ///
    /// Distinct identity is `(promQLTemplate, rangeMinutes, scopeParameters)`.
    /// Widgets sharing a PromQL template prefix must be coalesced before dispatch.
    /// Valid range: 1–5.
    public let maxPrometheusQueriesPerCycle: Int

    /// Maximum simultaneous in-flight queries across all data sources during
    /// one refresh cycle. Valid range: 1–8.
    public let maxSimultaneousQueries: Int

    /// Refresh interval in seconds. Default 30 s; energy-saver mode must use >= 60 s.
    /// Valid range: 5–60.
    public let refreshIntervalSeconds: Int

    /// Widget-level PromQL prefix coalescing. Must always be `true`; `false`
    /// is a spec error (ADR-0024).
    public let coalescingEnabled: Bool

    // MARK: Errors

    /// Validation errors for `WidgetBudget`.
    public enum ValidationError: Error, Sendable {
        /// `maxPrometheusQueriesPerCycle` is outside [1, 5].
        case maxQueriesOutOfRange(Int)
        /// `maxSimultaneousQueries` is outside [1, 8].
        case maxSimultaneousOutOfRange(Int)
        /// `refreshIntervalSeconds` is outside [5, 60].
        case refreshIntervalOutOfRange(Int)
        /// `coalescingEnabled` is `false`; must always be `true`.
        case coalescingMustBeEnabled
    }

    // MARK: Init

    /// Designated initialiser. Validates all invariants.
    ///
    /// - Throws: `ValidationError` when any constraint is violated.
    public init(
        maxPrometheusQueriesPerCycle: Int,
        maxSimultaneousQueries: Int,
        refreshIntervalSeconds: Int,
        coalescingEnabled: Bool
    ) throws {
        guard (1...5).contains(maxPrometheusQueriesPerCycle) else {
            throw ValidationError.maxQueriesOutOfRange(maxPrometheusQueriesPerCycle)
        }
        guard (1...8).contains(maxSimultaneousQueries) else {
            throw ValidationError.maxSimultaneousOutOfRange(maxSimultaneousQueries)
        }
        guard (5...60).contains(refreshIntervalSeconds) else {
            throw ValidationError.refreshIntervalOutOfRange(refreshIntervalSeconds)
        }
        guard coalescingEnabled else {
            throw ValidationError.coalescingMustBeEnabled
        }
        self.maxPrometheusQueriesPerCycle = maxPrometheusQueriesPerCycle
        self.maxSimultaneousQueries = maxSimultaneousQueries
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.coalescingEnabled = coalescingEnabled
    }

    /// Unchecked initialiser for use only in unit tests that pre-validate inputs.
    public static func unchecked(
        maxPrometheusQueriesPerCycle: Int = 5,
        maxSimultaneousQueries: Int = 8,
        refreshIntervalSeconds: Int = 30,
        coalescingEnabled: Bool = true
    ) -> WidgetBudget {
        // swiftlint:disable:next force_try
        try! WidgetBudget(
            maxPrometheusQueriesPerCycle: maxPrometheusQueriesPerCycle,
            maxSimultaneousQueries: maxSimultaneousQueries,
            refreshIntervalSeconds: refreshIntervalSeconds,
            coalescingEnabled: coalescingEnabled
        )
    }
}

// MARK: - Default budget

extension WidgetBudget {
    /// Canonical baseline used by scope presets that do not override individual fields.
    ///
    /// Mirrors `_defaultWidgetBudget` in `widget_budget.cue`.
    public static let `default` = WidgetBudget.unchecked()

    /// Energy-saver variant — doubles `refreshIntervalSeconds` to 60 s
    /// when `NSProcessInfo.processInfo.isLowPowerModeEnabled` returns `true`.
    ///
    /// Per ADR-0022 and spec invariant §3.
    public static let lowPower = WidgetBudget.unchecked(refreshIntervalSeconds: 60)
}

// MARK: - BudgetExhaustedError

/// Thrown by `WidgetQueryDispatchService` when the per-cycle query budget is exhausted.
public struct BudgetExhaustedError: Error, Sendable {
    /// Number of Prometheus queries dispatched in this cycle before exhaustion.
    public let queriesDispatched: Int
    /// Budget ceiling that was exceeded.
    public let budget: WidgetBudget

    /// Designated initialiser.
    public init(queriesDispatched: Int, budget: WidgetBudget) {
        self.queriesDispatched = queriesDispatched
        self.budget = budget
    }
}
