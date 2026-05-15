# DDD role: ChaosScenario
# Bounded context: cluster_connectivity
# Failure mode: F8 (kqueue / file-descriptor exhaustion)
# References: ADR-0041, ADR-0025, ADR-0029

Feature: kqueue file-descriptor exhaustion at session open
  As a cluster operator
  I need the app to reject new sessions gracefully when the FD limit is reached
  So that existing sessions are not disrupted and the error message is actionable

  Background:
    Given the per-process FD limit is artificially set to 1024 (via mock kqueue wrapper)
    And 1023 FDs are already allocated across active sessions and watch streams

  @chaos @io
  Scenario: Opening a new session when FD limit is reached returns a clear error
    Given the FD pool has exactly 1 available descriptor
    And opening a new session requires at least 3 FDs (socket + watch + control pipe)
    When the user attempts to open session "overflow-cluster"
    Then the session-open call fails immediately with error "Too many sessions"
    And the error is surfaced in the UI as "Cannot open session — system file-descriptor limit reached"
    And the new session is not created
    And the metric "session_open_fd_exhaustion_total" increments by 1

  @chaos @io
  Scenario: Existing sessions are unaffected when a new session is rejected due to FD exhaustion
    Given sessions "cluster-a", "cluster-b", and "cluster-c" are active and streaming events
    When a fourth session is rejected with "Too many sessions"
    Then sessions "cluster-a", "cluster-b", and "cluster-c" continue to deliver watch events
    And no existing watch stream is interrupted or reset
    And the health-probe for each existing session succeeds within the next poll interval

  @chaos @io
  Scenario: Closing an existing session frees FDs and allows a new session to be opened
    Given the FD pool is exhausted and one new session was rejected
    When the user closes session "cluster-a"
    Then the freed FDs are returned to the pool
    And the user can successfully open session "overflow-cluster"
    And the metric "session_open_fd_exhaustion_total" does not increment on the successful open
