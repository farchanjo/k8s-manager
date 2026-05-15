# DDD role: BehaviouralSpecification
# Bounded context: analytics_dashboard
# References: ADR-0016, ADR-0024
# CUE schema: contexts/analytics_dashboard/schemas/analytics_widget.cue

Feature: Dashboard widget Prometheus query budget — max 5 range queries per refresh
  As an operator
  I want the dashboard to coalesce widget queries to stay within a 5-query budget per refresh cycle
  So that the Prometheus server is not overwhelmed when ClusterOverview has many widgets

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Prometheus endpoint has been discovered at "http://prometheus-operated.monitoring.svc:9090"
    And the ClusterOverview dashboard is open with 11 widgets

  @happy @lifecycle
  Scenario: 11 widgets coalesced into 5 Prometheus range queries per refresh
    When the 30-second refresh timer fires
    Then the PrometheusQueryActor batches the 11 widget queries into at most 5 range query requests
    And queries that share the same metric family are coalesced (e.g., cpu_usage for multiple pods in one request)
    And at most 5 GET /api/v1/query_range requests are issued in the refresh cycle
    And all 11 widgets are updated with the results within the query timeout window

  @failure @lifecycle
  Scenario: One of the 5 coalesced queries times out — affected widgets show partial result indicator
    Given one of the 5 range queries takes longer than 30 seconds (the query timeout)
    When the query is cancelled at the 30-second timeout
    Then the widgets that depended on that query show a "partial results" indicator
    And the other 4 queries complete successfully and their widgets are fully updated
    And no error toast is shown (partial data is a degraded but non-fatal state)

  @happy @lifecycle
  Scenario: Refresh cycle does not overlap — next refresh waits for current to complete
    Given a refresh cycle is in progress (the 5 queries are in flight)
    When the 30-second timer fires again before the current cycle completes
    Then the new refresh cycle is skipped (not queued behind the in-flight cycle)
    And a log entry notes "Skipping refresh: previous cycle still in progress"
    And the next cycle starts after the in-flight cycle completes

  @failure @lifecycle
  Scenario: All 5 coalesced queries fail — widgets show error state with retry option
    Given the Prometheus endpoint returns HTTP 503 for all 5 queries in the refresh cycle
    When the refresh cycle fails completely
    Then all 11 widgets transition to "error" display state
    And the dashboard shows a global "Prometheus unavailable — retrying in 30s" banner
    And the next refresh cycle after 30 seconds retries the queries automatically
