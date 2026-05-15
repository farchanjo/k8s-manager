# DDD role: BehaviouralSpecification
# Bounded context: cluster_connectivity
# References: ADR-0011, ADR-0025, ADR-0029

Feature: Eight simultaneous cluster sessions — isolation and resource budget
  As a platform engineer managing multiple environments
  I want up to 8 cluster sessions active simultaneously with zero credential leakage
  So that requests destined for one cluster never use credentials from another

  Background:
    Given the application is running on a 10-core host
    And the session cap is set to 8 (default)

  @happy @lifecycle
  Scenario: Eight clusters activate simultaneously with isolated resources
    When the operator activates clusters "c1" through "c8" in rapid succession
    Then 8 ClusterSessionActors are spawned, one per cluster
    And each actor owns a unique HTTPClient instance not shared with any other actor
    And each actor owns a unique EventLoopGroup sized at max(2, 10/4) = 2 event loops
    And the total NIO event-loop thread count does not exceed 16 (8 × 2)
    And each actor's credential cache is initialised empty and scoped to that cluster only

  @security @lifecycle
  Scenario: Request against cluster A never uses credentials from cluster B
    Given ClusterSessionActors for "cluster-a" and "cluster-b" are both in "connected" state
    And "cluster-a" holds a bearer token "token-A" and "cluster-b" holds "token-B"
    When the adapter issues 10 concurrent requests against "cluster-a"
    Then every request carries the Authorization header "Bearer token-A"
    And no request carries "token-B"
    And the HTTPClient for "cluster-b" is not used for any of those 10 requests

  @failure @lifecycle
  Scenario: Ninth cluster activation is rejected with SessionCapExceeded
    Given ClusterSessionActors are running for "c1" through "c8" all in "connected" state
    When the operator attempts to activate cluster "c9"
    Then a SessionCapExceeded event is emitted
    And no ClusterSessionActor is spawned for "c9"
    And the application presents a prompt listing the 8 existing sessions for the operator to close one
    And all 8 existing sessions remain in "connected" state with their pools intact

  @lifecycle @persistence
  Scenario: Closing one session frees its resources and allows a new session
    Given 8 ClusterSessionActors are running and the session cap is reached
    When the operator closes "c1" via the session manager
    Then the ClusterSessionActor for "c1" transitions to "terminating" and then stops
    And the EventLoopGroup for "c1" is released (thread count decreases by 2)
    And the operator can now activate "c9" without a SessionCapExceeded event
    And the remaining 7 sessions are unaffected
