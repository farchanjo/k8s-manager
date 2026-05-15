# DDD role: BehaviouralSpecification
# Bounded context: metrics_observability
# References: ADR-0016

Feature: Prometheus range query cancelled at 30-second timeout
  As an operator
  I want slow Prometheus queries to be automatically cancelled after 30 seconds
  So that a slow or unresponsive Prometheus instance does not block the dashboard indefinitely

  Background:
    Given a Prometheus endpoint is active for "prod-us-east-1"
    And the PrometheusHTTPClient query timeout is configured to 30 seconds

  @failure @lifecycle
  Scenario: Query taking 35 seconds is cancelled and UI shows partial result indicator
    Given the Prometheus endpoint takes 35 seconds to respond to a range query
    When the PrometheusQueryActor dispatches a range query for the CPU usage widget
    And 30 seconds elapse without a response
    Then the URLSession task is cancelled by the 30-second timeout
    And a PrometheusClientError.queryTimeout is returned to the query actor
    And the CPU usage widget shows a "partial results" indicator with the last known data
    And no crash or unhandled error propagates to the UI layer

  @failure @lifecycle
  Scenario: Cancelled query does not block subsequent queries
    Given one range query timed out for the CPU widget
    When the 30-second refresh timer fires again
    Then a new query is dispatched for the CPU widget (the previous cancellation is cleared)
    And the new query runs independently with a fresh 30-second timeout
    And other widget queries in the same refresh cycle are not affected by the previous timeout

  @happy @lifecycle
  Scenario: Query responding in under 1 second displays data within the performance SLA
    Given the Prometheus endpoint responds within 800 milliseconds
    When the query is dispatched
    Then the response is received and decoded within 1 second of the dispatch
    And the widget renders the data within 1 second (performance SLA per ADR-0016)
    And no timeout fires

  @failure @lifecycle
  Scenario: All 5 coalesced queries time out in one refresh cycle — all widgets degrade
    Given all 5 coalesced Prometheus queries for the refresh cycle are slow (>30s each)
    When all 5 queries time out
    Then all affected widgets show "partial results" indicators
    And a global banner "Prometheus is slow — some metrics may be stale" is displayed
    And the next automatic refresh cycle (30s later) retries all 5 queries fresh
