# DDD role: BehaviouralSpecification
# Bounded context: _shared (cross-cutting)
# References: ADR-0024, ADR-0027, ADR-0035
# Rego policy: contexts/_shared/policies/performance_invariants.rego
# CUE schema: contexts/_shared/schemas/performance_budgets.cue

Feature: Performance budget breach — policy enforcement and telemetry on ceiling violations
  As a platform engineer maintaining K8sManager quality gates
  I want the performance_invariants.rego policy to detect budget breaches in MetricsSamples
  So that CI and the self-monitoring surface can catch regressions before they reach users

  Background:
    Given the SelfMonitoringSampler is active and collecting MetricsSamples every 5 seconds
    And the performance_invariants.rego policy is loaded by the conftest test suite

  @policy @invariant
  Scenario: Widget query budget breach — dashboardQueriesPerCycle > 5 cancels the query cycle
    Given the PrometheusQueryActor dispatches 6 range queries in one refresh cycle
    And the SelfMonitoringSampler captures a MetricsSample with dashboardQueriesPerCycle=6
    When the performance_invariants.rego policy evaluates the sample
    Then the deny set contains "dashboard query budget exceeded: 6 queries per cycle (limit 5)"
    And the allow decision is false
    And the PrometheusQueryActor cancels the over-budget queries for the current cycle
    And the SelfMonitoringSampler logs a "budget.query_exceeded" telemetry entry
         containing the cycle timestamp and observed query count
    And no user-facing error dialog is displayed (budget breach is an internal platform event)

  @policy @invariant
  Scenario: Tray refresh latency breach — frameTimeMs > 16 ms logs telemetry with no user impact
    Given the SwiftUI main render loop records a frame evaluation that takes 17.5 ms
    And the SelfMonitoringSampler captures a MetricsSample with frameTimeMs=17.5
    When the performance_invariants.rego policy evaluates the sample
    Then the deny set contains a message matching "frame budget exceeded"
    And the allow decision is false
    And the breach is written to the diagnostics telemetry log at level WARN
         with the observed frameTimeMs and the 16 ms ceiling
    And no toast, banner, or modal is shown to the operator
    And all existing UI interactions continue normally — the breach is invisible to the end-user
