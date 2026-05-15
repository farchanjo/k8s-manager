# DDD role: ChaosScenario
# Bounded context: metrics_observability
# References: ADR-0016, ADR-0027, ADR-0036

Feature: Prometheus endpoint flaps — intermittent 503 responses trigger retry with backoff
  As an operator
  I want the metrics dashboard to show clearly stale data with a staleness timestamp
  when the Prometheus endpoint is intermittently unavailable
  So that I know the data age rather than seeing silently stale charts

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Prometheus endpoint is active at "http://prometheus-operated.monitoring.svc:9090"
    And the ClusterOverview dashboard is displaying live metric charts

  @chaos @failure
  Scenario: Prometheus endpoint returns 503 intermittently — queries retried with exponential backoff
    Given the Prometheus endpoint alternates between HTTP 200 and HTTP 503 responses at random
    When the PrometheusQueryActor dispatches a range query and receives HTTP 503
    Then the query is retried using exponential backoff starting at 1 second
    And subsequent 503 responses each double the backoff interval up to a cap of 30 seconds
    And during each backoff interval the widget displays its last successfully rendered data
    And no new HTTP request is issued to Prometheus until the current backoff interval elapses

  @chaos @failure
  Scenario: Consecutive 503 responses exhaust retry budget — chart shows stale data with age label
    Given the Prometheus endpoint has returned HTTP 503 for 3 consecutive query attempts
    When the last retry in the backoff schedule is also rejected with HTTP 503
    Then the PrometheusQueryActor marks the endpoint as "unreachable" for this refresh cycle
    And each chart widget renders its last successfully fetched data points
    And a "stale data — N min old" label appears below each affected chart
    And the staleness N is calculated as the elapsed time since the last successful query response
    And a "Prometheus unavailable — retrying in 30s" banner appears at the top of the dashboard
    And no unhandled error propagates to the UI layer

  @chaos @recovery
  Scenario: Endpoint recovers after flap — stale indicators cleared automatically
    Given the dashboard is showing "stale data — 3 min old" labels due to prior 503 responses
    When the next scheduled query succeeds with HTTP 200
    Then all "stale data" labels are cleared from the chart widgets
    And the charts re-render with the fresh data from the successful response
    And the "Prometheus unavailable" banner is dismissed
    And the PrometheusQueryActor resets the endpoint status to "healthy"
