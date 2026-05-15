# DDD role: BehaviouralSpecification
# Bounded context: port_forwarding
# References: ADR-0011, ADR-0014, ADR-0025

Feature: Port-forward tunnel establishment — listener bind and first connection
  As an operator
  I want to establish a port-forward tunnel to a running Pod
  So that I can access in-cluster services directly from my local tools

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Pod named "postgres-0" in namespace "db" is in Running state with port 5432 exposed

  @happy @lifecycle
  Scenario: Port-forward tunnel opens and first connection round-trips bytes
    When the operator opens a port-forward from local port 15432 to Pod port 5432 on "postgres-0"
    Then a WebSocket upgrade to "portforward.k8s.io" is negotiated with the API server
    And a TCP server socket is bound to 127.0.0.1:15432
    And the session transitions from "opening" to "running"
    And a #ListenerBound event is emitted with effectiveLocalPort 15432 and isNetworkExposed false
    When a local TCP client connects to 127.0.0.1:15432 and writes "PING\n"
    Then the write is forwarded as a binary WebSocket frame with port-index byte 0x01 and channel byte 0x00
    And the response bytes from the Pod are delivered back to the TCP client
    And the #BytesTransferred event is emitted with non-zero sent and received byte counts

  @happy @lifecycle
  Scenario: System-assigned dynamic port is captured and shown in UI
    When the operator opens a port-forward with localPort 0 (dynamic assignment)
    Then the kernel assigns an ephemeral port (e.g., 51234)
    And the session aggregate records effectiveLocalPort as 51234
    And the UI displays the assigned port to the operator

  @failure @lifecycle
  Scenario: WebSocket upgrade failure transitions session to error
    Given the API server returns HTTP 403 Forbidden to the upgrade request
    When the operator attempts to open a port-forward to "postgres-0" port 5432
    Then the WebSocket upgrade fails
    And the session transitions from "opening" to "error"
    And a #SessionFailed event is emitted with a non-credential error description
    And no local TCP socket is bound

  @security @lifecycle
  Scenario: Non-loopback bind requires an explicit operator warning
    When the operator configures bindAddress "0.0.0.0" for a port-forward session
    Then the application displays a warning "Tunnel will be accessible from the local network, not just localhost"
    And the #ListenerBound event is emitted with isNetworkExposed equal to true
    And the operator must explicitly acknowledge before the session transitions to "running"
