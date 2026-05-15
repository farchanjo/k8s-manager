# DDD role: BehaviouralSpecification
# Bounded context: port_forwarding
# References: ADR-0011, ADR-0014, ADR-0025

Feature: Port-forward sessions torn down when cluster session closes
  As an operator
  I want all port-forward sessions for a cluster to close automatically when I disconnect that cluster
  So that dangling local listeners do not accumulate and local ports are released

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And three port-forward sessions are active against "prod-us-east-1":
      | Session | Pod       | LocalPort |
      | pf-1    | postgres-0 | 15432    |
      | pf-2    | redis-0    | 16379    |
      | pf-3    | app-0      | 18080    |

  @happy @lifecycle
  Scenario: Cluster disconnect tears down all three port-forward sessions within 5 seconds
    When the operator manually disconnects "prod-us-east-1"
    Then the ClusterSessionActor initiates cooperative shutdown on all port-forward sessions
    And all three sessions transition to "closing" and then "closed"
    And all three local TCP listeners are unbound within 5 seconds of the disconnect signal
    And a #SessionClosed event is emitted for each of pf-1, pf-2, and pf-3
    And ports 15432, 16379, and 18080 are available for other processes to bind

  @happy @lifecycle
  Scenario: App quit within 500 ms deadline closes all port-forward sessions
    Given the application receives applicationWillTerminate
    When the 500 millisecond shutdown deadline starts
    Then all port-forward sessions for all clusters transition to "closing"
    And all TCP listeners are unbound within the 500 ms deadline
    And the process exits cleanly without dangling file descriptors

  @failure @lifecycle
  Scenario: WebSocket close handshake timeout during shutdown does not block exit
    Given one port-forward session is in "closing" state
    And the API server does not send a WebSocket Close echo within 200 milliseconds
    When the 200 ms timeout elapses
    Then the PortForwardManagerActor cancels the underlying URLSessionWebSocketTask
    And the local TCP listener is closed regardless of the missing server echo
    And the session transitions to "closed"
    And the shutdown sequence continues without blocking

  @lifecycle @happy
  Scenario: Only sessions for the closed cluster are torn down — others remain
    Given a second ClusterSessionActor for "staging-eu-west" is also in "connected" state
    And "staging-eu-west" has one port-forward session "pf-4" on local port 19000
    When the operator disconnects only "prod-us-east-1"
    Then sessions pf-1, pf-2, pf-3 are closed for "prod-us-east-1"
    And session pf-4 for "staging-eu-west" remains in "running" state
    And port 19000 remains bound to the "staging-eu-west" listener
