# DDD role: BehaviouralSpecification
# Bounded context: terminal_session
# References: ADR-0011, ADR-0017, ADR-0025

Feature: Pod exec session open — v5 subprotocol negotiation and channel separation
  As an operator
  I want to open an interactive terminal session into a running container
  So that I can execute commands and inspect the container's state directly

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Pod "web-0" in namespace "default" is in Running state with one container "nginx"

  @happy @lifecycle
  Scenario: Exec session opens with v5 subprotocol and channels are separated
    When the operator opens an exec terminal for "web-0" container "nginx"
    Then a WebSocket upgrade request is sent with "Sec-WebSocket-Protocol: v5.channel.k8s.io"
    And the server negotiates "v5.channel.k8s.io" in the response
    And the TerminalSessionActor is spawned for this session
    And the session state transitions from "opening" to "open"
    And stdin frames from the operator are prefixed with channel byte 0x00
    And stdout frames from the container are delivered on channel byte 0x01
    And stderr frames from the container are delivered on channel byte 0x02
    And error messages (exit code) arrive on channel byte 0x03

  @happy @lifecycle
  Scenario: Operator types a command and receives output on the correct channel
    Given the exec session is in "open" state
    When the operator types "ls -la\n" in the terminal UI
    Then a WebSocket binary frame is sent with first byte 0x00 followed by the ASCII bytes of "ls -la\n"
    And the container's response is received on channel 0x01 (stdout)
    And the terminal renderer displays the response in the stdout area

  @failure @lifecycle
  Scenario: WebSocket upgrade rejected with 403 Forbidden
    Given the cluster RBAC does not permit pods/exec for the operator's identity
    When the operator opens an exec terminal for "web-0"
    Then the WebSocket upgrade returns HTTP 403 Forbidden
    And the session transitions from "opening" to "error"
    And a "Session failed: 403 Forbidden — check RBAC permissions for pods/exec" message is shown
    And no TerminalSessionActor receive loop is started

  @happy @lifecycle
  Scenario: Multiple concurrent exec sessions each own an isolated TerminalSessionActor
    When the operator opens exec terminals for "web-0", "api-0", and "worker-0" simultaneously
    Then three TerminalSessionActors are spawned, one per session
    And each actor holds its own URLSessionWebSocketTask
    And closing the session for "web-0" sends Task.cancel only to the "web-0" actor
    And the "api-0" and "worker-0" sessions remain in "open" state
