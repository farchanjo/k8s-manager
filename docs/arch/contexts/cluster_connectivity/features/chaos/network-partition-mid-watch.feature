# DDD role: ChaosScenario
# Bounded context: cluster_connectivity
# Failure mode: F1 (API server unreachable), F5 (watch stream interrupted)
# References: ADR-0041, ADR-0025, ADR-0026

Feature: Network partition during active watch stream
  As a cluster operator
  I need the watch adapter to survive a 60-second API server blackout
  So that the UI stays informative during brief network partitions and recovers cleanly

  Background:
    Given a cluster session "prod-eu" is established and healthy
    And the resource watch for "pods" in namespace "default" is active
    And the steady-state metric "watch_events_received_total" is incrementing

  @chaos @network
  Scenario: API server unreachable for 60 seconds triggers Degraded state with exponential backoff
    Given the watch stream has delivered at least 5 events without error
    When the network route to the API server is blocked for 60 seconds
    Then the adapter transitions to state "Degraded" within 5 seconds of the first read timeout
    And the UI surfaces the badge "Cluster Unreachable" on the cluster tile
    And the adapter applies exponential backoff with base 1s and cap 30s between reconnect attempts
    And no reconnect attempt occurs more frequently than the current backoff interval
    And the metric "watch_reconnect_attempts_total" increments on each attempt

  @chaos @network
  Scenario: Recovery after 60-second partition emits WatchStreamReconnected with new resource version
    Given the adapter is in state "Degraded" after a 60-second network partition
    When the network route to the API server is restored
    Then the adapter reconnects within one backoff cycle (max 30 seconds)
    And the adapter transitions from "Degraded" to "Connected"
    And the event "WatchStreamReconnected" is emitted with a "resourceVersion" field greater than the last known RV
    And the UI badge "Cluster Unreachable" is cleared
    And subsequent watch events resume delivery without duplication

  @chaos @network
  Scenario: Partial connectivity (DNS resolves but TCP RST) is treated as unreachable
    Given the DNS for the API server resolves correctly
    When all TCP connections to port 6443 receive immediate RST
    Then the adapter treats the condition as API-server unreachable
    And state transitions to "Degraded" following the same backoff policy as a full blackout
    And the error cause surfaced in telemetry includes "connection refused"
