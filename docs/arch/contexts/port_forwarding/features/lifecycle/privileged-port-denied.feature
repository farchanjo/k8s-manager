# DDD role: BehaviouralSpecification
# Bounded context: port_forwarding
# References: ADR-0012, ADR-0014

Feature: Privileged local port denied by policy
  As a security-conscious operator
  I want the application to block port-forward requests targeting privileged local ports below 1024
  So that accidental elevation of network privileges is prevented

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Pod "nginx-0" in namespace "web" exposes port 80

  @security @lifecycle
  Scenario: Request for local port 80 is denied by Rego policy before any network call
    When the operator requests a port-forward with localPort 80 to Pod port 80
    Then the port-forward policy Rego rule "deny_privileged_local_port" is evaluated
    And the rule returns a deny decision because 80 is below 1024
    And no WebSocket upgrade request is issued
    And no bind(2) syscall is made
    And an audit log entry is written for the denied request
    And the UI shows "Port 80 is a privileged port — use a port above 1023 (e.g., 8080)"

  @security @lifecycle
  Scenario: Request for local port 443 is similarly denied
    When the operator requests a port-forward with localPort 443 to Pod port 443
    Then the Rego policy denies the request (443 < 1024)
    And the audit log records the denial with the requested local port

  @happy @lifecycle
  Scenario: Non-privileged port 8080 passes the policy check
    When the operator requests a port-forward with localPort 8080 to Pod port 80
    Then the Rego policy allows the request (8080 >= 1024)
    And the WebSocket upgrade proceeds normally
    And the session transitions to "running"

  @security @lifecycle
  Scenario: Dynamic port 0 passes the policy — kernel chooses a non-privileged port
    When the operator requests a port-forward with localPort 0
    Then the Rego policy allows the request (0 is interpreted as "let the kernel choose")
    And the kernel assigns an ephemeral port above 1023
    And the session transitions to "running"
