# DDD role: BehaviouralSpecification
# Bounded context: port_forwarding
# References: ADR-0014

Feature: Local port conflict detection and alternative suggestion
  As an operator
  I want to be informed when a requested local port is already in use
  So that I can choose an alternative port without seeing a raw OS error

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Pod "postgres-0" in namespace "db" exposes port 5432

  @failure @lifecycle
  Scenario: Fixed local port already in use surfaces a user-friendly error
    Given port 15432 on 127.0.0.1 is already bound by another process
    When the operator requests a port-forward with localPort 15432 to Pod port 5432
    Then the bind(2) syscall fails with EADDRINUSE
    And the session transitions from "opening" to "error"
    And a #SessionFailed event is emitted with reason "local-port-in-use" and the conflicting port number
    And the UI shows: "Port 15432 is already in use — try a different port (e.g., 25432)"
    And the WebSocket upgrade is NOT attempted (port binding is checked first)

  @happy @lifecycle
  Scenario: Requesting dynamic port 0 avoids any conflict
    When the operator requests a port-forward with localPort 0
    Then the kernel assigns an ephemeral port successfully
    And the session transitions to "running"
    And no EADDRINUSE error occurs

  @happy @lifecycle
  Scenario: Re-attempting with an alternative port after a conflict succeeds
    Given the operator was informed that port 15432 is in use
    When the operator enters port 25432 as the alternative
    Then the bind(2) syscall succeeds on port 25432
    And the session transitions to "running" with effectiveLocalPort 25432

  @security @lifecycle
  Scenario: No payload content is logged when local port binding fails
    Given port 15432 is in use and the session transitions to "error"
    When the #SessionFailed event is processed
    Then the error detail does not include any credential, token, or payload bytes
    And the log entry contains only the port number and the EADDRINUSE reason code
