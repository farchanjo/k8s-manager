# DDD role: ChaosScenario
# Bounded context: cluster_connectivity
# Failure mode: F3 (API server rate-limiting / 429 Too Many Requests)
# References: ADR-0041, ADR-0025, ADR-0026

Feature: API server returns 429 with Retry-After header
  As a cluster operator
  I need the adapter to honor server-side rate-limit signals
  So that the app does not amplify load on an already-stressed API server

  Background:
    Given a cluster session "prod-eu" is established and healthy
    And the API server rate-limit policy is set to "low" (simulated via mock)

  @chaos @network
  Scenario: 429 with Retry-After: 10s causes adapter to pause and display Throttled badge
    Given a LIST request for "pods" is issued
    When the API server responds with HTTP 429 and header "Retry-After: 10"
    Then the adapter does NOT retry before 10 seconds have elapsed
    And the UI displays the badge "Throttled" on the cluster tile within 1 second of the 429
    And no additional API requests are dispatched to this cluster during the wait
    And after 10 seconds the adapter retries the original request
    And on success the "Throttled" badge is cleared

  @chaos @network
  Scenario: 429 without Retry-After header falls back to 5-second default pause
    Given a LIST request for "services" is issued
    When the API server responds with HTTP 429 and no "Retry-After" header
    Then the adapter applies a default pause of 5 seconds before retrying
    And the UI displays the badge "Throttled" during the pause
    And the metric "api_throttle_events_total" increments by 1

  @chaos @network
  Scenario: Repeated 429 responses on watch reconnect are counted and surfaced in diagnostics
    Given the watch stream reconnects after a network partition
    When the adapter receives three consecutive 429 responses on reconnect attempts
    Then the adapter applies Retry-After delay for each response
    And the diagnostic panel reports "Throttled 3 times in last 60s"
    And on the fourth attempt that succeeds the watch stream resumes normally
