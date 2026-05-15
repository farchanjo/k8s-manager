# DDD role: BehaviouralSpecification
# Bounded context: port_forwarding
# References: ADR-0014

Feature: Port-forward tunnel drop — no auto-reconnect policy
  As an operator
  I want to be explicitly informed when a port-forward tunnel drops due to a Pod restart
  So that I can make a deliberate decision about whether to re-establish the connection

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a port-forward session for "postgres-0" port 5432 is in "running" state

  @failure @lifecycle
  Scenario: Pod restarts — tunnel drops and operator is informed without auto-reconnect
    When "postgres-0" is deleted and a new Pod "postgres-0" is started by the StatefulSet controller
    Then the WebSocket connection closes unexpectedly (server sends a close frame or TCP resets)
    And the port-forward session transitions from "running" to "error"
    And a #SessionFailed event is emitted with the reason "pod-restarted-or-websocket-closed"
    And the local TCP listener is closed (no new connections are accepted)
    And NO automatic reconnect is attempted
    And the UI shows an affordance "Reconnect" for the operator to manually re-open the session

  @failure @lifecycle
  Scenario: Manual reconnect creates a new PortForwardSession rather than reusing the old one
    Given a port-forward session for "postgres-0" is in "error" state
    When the operator clicks "Reconnect" in the UI
    Then a new PortForwardSession aggregate is created (the old session is not reused)
    And a new WebSocket upgrade is negotiated
    And the new session transitions from "opening" to "running"
    And the previous errored session aggregate is discarded

  @failure @lifecycle
  Scenario: Transient network blip drops tunnel — operator must restart manually
    Given the local network is interrupted for 5 seconds
    When the network interruption causes the WebSocket TCP connection to reset
    Then the port-forward session transitions to "error"
    And the UI surfaces the "network-interrupted" reason
    And no reconnect task is spawned in the background

  @lifecycle @happy
  Scenario: Clean stop by operator transitions session through closing to closed
    Given the port-forward session for "postgres-0" is in "running" state
    When the operator presses "Stop" in the port-forward manager
    Then the PortForwardManagerActor sends a WebSocket Close frame (code 1000)
    And the actor waits up to 200 milliseconds for the server's Close echo
    And the session transitions through "closing" to "closed"
    And the local TCP listener is closed synchronously after the WebSocket task is cancelled
    And a #SessionClosed event is emitted
