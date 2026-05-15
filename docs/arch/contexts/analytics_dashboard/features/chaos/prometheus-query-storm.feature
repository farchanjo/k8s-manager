# DDD role: ChaosScenario
# Bounded context: analytics_dashboard
# References: ADR-0024, ADR-0016, ADR-0027
# CUE schema: contexts/analytics_dashboard/schemas/analytics_widget.cue
# CUE schema: contexts/_shared/schemas/performance_budgets.cue (#DashboardBudget)

Feature: Prometheus query storm — 100 simultaneous widget queries exceed budget
  As an operator with many dashboards open
  I want the analytics dashboard to degrade gracefully to a text-only state
  So that a query storm does not render the Prometheus server unresponsive

  Background:
    Given a ClusterSessionActor for "perf-test-cluster" is in "connected" state
    And a Prometheus endpoint has been discovered at "http://prometheus-operated.monitoring.svc:9090"
    And the operator has opened 20 ClusterOverview dashboards each with 5 widgets (100 widgets total)

  @chaos @failure
  Scenario: 100 simultaneous widget queries trigger query budget enforcement
    When all 100 widgets attempt to refresh at the same 30-second interval boundary
    Then the PrometheusQueryActor enforces the 5-query-per-cycle budget per ADR-0024
    And queries beyond the budget of 5 are queued and issued in subsequent cycles
    And no more than 5 GET /api/v1/query_range requests are in-flight simultaneously
    And no Prometheus server receives more than 5 concurrent requests from this client
    And the performance_invariants.rego policy evaluates dashboardQueriesPerCycle as <=5

  @chaos @failure
  Scenario: Query budget breach detected — dashboard degrades to text-only state
    Given the coalescing logic fails and 6 Prometheus range queries are dispatched in one cycle
    When the performance_invariants.rego policy evaluates the MetricsSample
    Then the policy emits a deny for "dashboard query budget exceeded: 6 queries per cycle (limit 5)"
    And the PrometheusQueryActor cancels all in-flight queries for this cycle
    And every widget transitions to a text-only fallback state showing its last known scalar value
    And a "Query budget exceeded — charts temporarily disabled" banner appears in the dashboard header
    And an "events.dropped" diagnostic entry is written with the query count and cycle timestamp
    And no Prometheus server is contacted again until the next scheduled refresh cycle

  @chaos @performance
  Scenario: Storm resolves — dashboard recovers from text-only state on next cycle
    Given the dashboard has degraded to text-only state after a query budget breach
    When the 30-second refresh timer fires and the cycle count is back within budget
    Then the PrometheusQueryActor dispatches at most 5 coalesced queries for the next cycle
    And widgets transition from text-only back to chart mode as results arrive
    And the "Query budget exceeded" banner is dismissed automatically
    And the SelfMonitoringSampler records a "dashboard-recovered" event in the diagnostics log
