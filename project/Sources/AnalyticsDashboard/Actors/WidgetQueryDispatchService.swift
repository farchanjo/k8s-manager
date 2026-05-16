// Actors/WidgetQueryDispatchService.swift — analytics_dashboard bounded context
// DDD role: DomainService (actor)
// Spec:      docs/arch/contexts/analytics_dashboard/domain/narrative.md §Domain Services
// ADR ref:   ADR-0024 (Analytics Dashboard Bounded Context — query budget + coalescing)
// ADR ref:   ADR-0022 (low-power mode — refresh interval doubling)
// ADR ref:   ADR-0044 (PromQL injection prevention — placeholder substitution)
//
// Dispatches widget queries with budget enforcement and query coalescing.
// Doubles refreshIntervalSeconds when macOS low-power mode is active.

import Dependencies
import Foundation

// MARK: - ScopeParameters

/// Scope-derived placeholder values substituted into PromQL templates.
///
/// `WidgetQueryDispatchService` substitutes these before dispatching queries (ADR-0044).
public struct ScopeParameters: Sendable {
    public let namespace: String?
    public let podName: String?
    public let nodeName: String?
    public let serviceName: String?
    public let containerName: String?
    public let releaseName: String?

    /// Designated initialiser.
    public init(
        namespace: String? = nil,
        podName: String? = nil,
        nodeName: String? = nil,
        serviceName: String? = nil,
        containerName: String? = nil,
        releaseName: String? = nil
    ) {
        self.namespace = namespace
        self.podName = podName
        self.nodeName = nodeName
        self.serviceName = serviceName
        self.containerName = containerName
        self.releaseName = releaseName
    }

    /// Derives scope parameters from a `DashboardScope`.
    public static func from(scope: DashboardScope) -> ScopeParameters {
        switch scope {
        case .clusterOverview:
            return ScopeParameters()
        case .namespaceDetail(let ns):
            return ScopeParameters(namespace: ns)
        case .podDetail(let ns, let pod):
            return ScopeParameters(namespace: ns, podName: pod)
        case .nodeDetail(let node):
            return ScopeParameters(nodeName: node)
        case .workloadDetail(_, let ns, let name):
            return ScopeParameters(namespace: ns, serviceName: name)
        case .serviceDetail(let ns, let name):
            return ScopeParameters(namespace: ns, serviceName: name)
        case .helmReleaseDetail(let ns, let release, _):
            return ScopeParameters(namespace: ns, releaseName: release)
        case .debugTimeline:
            return ScopeParameters()
        case .topologyGraph:
            return ScopeParameters()
        }
    }

    /// Substitutes placeholders in a PromQL template string.
    ///
    /// Placeholders: `{namespace}`, `{pod}`, `{node}`, `{service}`,
    /// `{container}`, `{release_name}`. Unresolved placeholders are left intact.
    public func substitute(into template: String) -> String {
        var result = template
        if let ns = namespace       { result = result.replacingOccurrences(of: "{namespace}", with: ns) }
        if let pod = podName        { result = result.replacingOccurrences(of: "{pod}", with: pod) }
        if let node = nodeName      { result = result.replacingOccurrences(of: "{node}", with: node) }
        if let svc = serviceName    { result = result.replacingOccurrences(of: "{service}", with: svc) }
        if let c = containerName    { result = result.replacingOccurrences(of: "{container}", with: c) }
        if let r = releaseName      { result = result.replacingOccurrences(of: "{release_name}", with: r) }
        return result
    }
}

// MARK: - QueryCoalescingKey

/// Identity key for query coalescing within a single refresh cycle.
///
/// Two widgets sharing the same `(resolvedPromQL, rangeMinutes)` tuple are
/// coalesced into a single upstream request (spec invariant §2).
private struct QueryCoalescingKey: Hashable {
    let resolvedPromQL: String
    let rangeMinutes: Int
}

// MARK: - WidgetQueryDispatchService

/// Actor that dispatches widget queries with budget enforcement and coalescing.
///
/// Responsibilities:
/// - Resolves each `WidgetSlot` in the active `Dashboard` to its data-source port.
/// - Substitutes scope-derived placeholders (`{namespace}`, `{pod}`, etc.) into
///   PromQL templates (ADR-0044 injection prevention).
/// - Coalesces duplicate `(resolvedPromQL, rangeMinutes)` queries within a single
///   refresh cycle — each distinct expression is sent at most once (spec §2).
/// - Enforces the per-cycle Prometheus query budget from `WidgetBudget` (ADR-0024).
/// - Doubles `refreshIntervalSeconds` when `NSProcessInfo.isLowPowerModeEnabled`
///   returns `true` (ADR-0022, spec §3).
public actor WidgetQueryDispatchService {

    // MARK: Public state

    /// The budget configuration governing this service instance.
    public let budget: WidgetBudget

    /// Number of distinct Prometheus range queries dispatched in the current cycle.
    public private(set) var queriesDispatchedThisCycle: Int

    // MARK: Private state

    /// Coalescing cache for the current refresh cycle.
    /// Key: `QueryCoalescingKey`; value: resolved `[MetricSeries]` result.
    private var coalescedRangeCache: [QueryCoalescingKey: [MetricSeries]]

    /// Coalescing cache for instant queries this cycle.
    private var coalescedInstantCache: [String: [InstantSample]]

    @Dependency(\.analyticsMetricsQuery) private var metricsQuery

    // MARK: Init

    /// Creates the service with the given query budget.
    ///
    /// - Parameter budget: Budget configuration. Defaults to `WidgetBudget.default`.
    public init(budget: WidgetBudget = .default) {
        self.budget = budget
        self.queriesDispatchedThisCycle = 0
        self.coalescedRangeCache = [:]
        self.coalescedInstantCache = [:]
    }

    // MARK: - Cycle management

    /// Resets the per-cycle query counter and coalescing cache.
    ///
    /// Must be called once at the start of each auto-refresh cycle.
    public func resetCycle() {
        queriesDispatchedThisCycle = 0
        coalescedRangeCache.removeAll(keepingCapacity: true)
        coalescedInstantCache.removeAll(keepingCapacity: true)
    }

    /// Returns the effective refresh interval in seconds, accounting for low-power mode.
    ///
    /// When `NSProcessInfo.processInfo.isLowPowerModeEnabled` is `true`,
    /// the interval is doubled (spec §3, ADR-0022).
    public func effectiveRefreshInterval() -> Int {
        let base = budget.refreshIntervalSeconds
        return NSProcessInfo.processInfo.isLowPowerModeEnabled ? base * 2 : base
    }

    // MARK: - Range query dispatch

    /// Dispatches a PromQL range query for the given widget, coalescing identical requests.
    ///
    /// Substitutes scope parameters into the `promQLTemplate` before dispatching.
    /// Identical `(resolvedPromQL, rangeMinutes)` pairs within the same cycle return
    /// the cached result without consuming additional budget.
    ///
    /// - Parameters:
    ///   - promQLTemplate: Raw PromQL template from the widget configuration.
    ///   - rangeMinutes: Look-back window.
    ///   - scopeParams: Placeholder substitution values from the active scope.
    ///   - kubernetesContextId: Cluster context identifier.
    /// - Returns: List of labeled time series.
    /// - Throws: `BudgetExhaustedError` when the cycle budget is exhausted.
    public func rangeQuery(
        promQLTemplate: String,
        rangeMinutes: Int,
        scopeParams: ScopeParameters,
        kubernetesContextId: String
    ) async throws -> [MetricSeries] {
        let resolved = scopeParams.substitute(into: promQLTemplate)
        let key = QueryCoalescingKey(resolvedPromQL: resolved, rangeMinutes: rangeMinutes)

        // Return coalesced result if already fetched this cycle
        if let cached = coalescedRangeCache[key] { return cached }

        // Enforce budget before issuing new request
        try enforceBudget()

        let series = try await metricsQuery.rangeQuery(
            promQL: resolved,
            rangeMinutes: rangeMinutes,
            kubernetesContextId: kubernetesContextId
        )
        coalescedRangeCache[key] = series
        queriesDispatchedThisCycle += 1
        return series
    }

    /// Dispatches a PromQL instant query, coalescing identical resolved expressions.
    ///
    /// - Parameters:
    ///   - promQLTemplate: Raw PromQL template from the widget configuration.
    ///   - scopeParams: Placeholder substitution values from the active scope.
    ///   - kubernetesContextId: Cluster context identifier.
    /// - Returns: List of instant-vector samples.
    /// - Throws: `BudgetExhaustedError` when the cycle budget is exhausted.
    public func instantQuery(
        promQLTemplate: String,
        scopeParams: ScopeParameters,
        kubernetesContextId: String
    ) async throws -> [InstantSample] {
        let resolved = scopeParams.substitute(into: promQLTemplate)

        if let cached = coalescedInstantCache[resolved] { return cached }

        try enforceBudget()

        let samples = try await metricsQuery.instantQuery(
            promQL: resolved,
            kubernetesContextId: kubernetesContextId
        )
        coalescedInstantCache[resolved] = samples
        queriesDispatchedThisCycle += 1
        return samples
    }

    /// Returns the number of distinct queries dispatched in the current cycle.
    public func queriesUsedThisCycle() -> Int {
        queriesDispatchedThisCycle
    }

    /// Returns `true` when the budget ceiling has been reached for this cycle.
    public func isBudgetExhausted() -> Bool {
        queriesDispatchedThisCycle >= budget.maxPrometheusQueriesPerCycle
    }

    // MARK: - Private helpers

    /// Throws `BudgetExhaustedError` when the cycle limit has been reached.
    private func enforceBudget() throws {
        guard queriesDispatchedThisCycle < budget.maxPrometheusQueriesPerCycle else {
            throw BudgetExhaustedError(queriesDispatched: queriesDispatchedThisCycle, budget: budget)
        }
    }
}
