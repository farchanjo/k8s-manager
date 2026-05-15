# DDD role: ChaosScenario
# Bounded context: port_forwarding
# Failure mode: concurrency (local port conflict after tunnel close)
# References: ADR-0041, ADR-0028

Feature: Local port stolen by another process between tunnel close and re-open
  As a cluster operator
  I need the app to detect local port conflicts and suggest an alternative
  So that I am not left with a silent bind failure or a cryptic OS error

  Background:
    Given tunnel "T1" was previously active on local port 8080
    And tunnel "T1" has been closed by the operator

  @chaos @concurrency
  Scenario: Another process binds port 8080 before the operator re-opens the tunnel
    Given a separate OS process has bound local port 8080 after "T1" was closed
    When the operator attempts to re-open tunnel "T1" on local port 8080
    Then the bind call returns EADDRINUSE
    And the app does NOT crash or silently fail
    And the UI surfaces "Port 8080 is already in use by another process"
    And the UI suggests the next available ephemeral port (e.g., 8081)

  @chaos @concurrency
  Scenario: Operator accepts suggested alternative port and tunnel opens successfully
    Given the app has suggested port 8081 as an alternative
    When the operator accepts the suggestion
    Then the tunnel "T1" is opened on local port 8081 → pod "nginx-abc123" :80
    And the tunnel state transitions to "Active"
    And the UI shows "Active — :8081 → nginx-abc123 :80"

  @chaos @concurrency
  Scenario: Operator manually specifies a different port and tunnel opens successfully
    Given the app has detected the port conflict on 8080
    When the operator manually enters port 9090 in the port field
    And the operator clicks "Open"
    Then the tunnel is opened on local port 9090
    And the tunnel state transitions to "Active"
