# DDD role: ChaosScenario
# Bounded context: port_forwarding
# Failure mode: F15 (pod restart tears down active port-forward tunnel)
# References: ADR-0041, ADR-0026, ADR-0028

Feature: Pod restart tears down active port-forward tunnel without auto-reconnect
  As a cluster operator
  I need the tunnel to be explicitly marked Disconnected when the target pod restarts
  So that I am aware of the interruption and can consciously decide to reconnect

  Background:
    Given a port-forward tunnel "T1" is active: local :8080 → pod "nginx-abc123" :80
    And the tunnel has forwarded at least 100 bytes successfully
    And no auto-reconnect policy is configured

  @chaos @network
  Scenario: Pod restart causes WebSocket error and tunnel transitions to Disconnected
    When the pod "nginx-abc123" is deleted and replaced by "nginx-def456" (rolling restart)
    Then the port-forward WebSocket connection for "T1" receives a close frame or read error
    And the tunnel "T1" transitions from "Active" to "Disconnected" within 5 seconds
    And the UI shows tunnel "T1" as "Disconnected — pod restarted"
    And NO automatic reconnect attempt is made

  @chaos @network
  Scenario: Operator manually restarts the tunnel after pod restart
    Given tunnel "T1" is in state "Disconnected"
    When the operator clicks "Reconnect" for tunnel "T1"
    Then the app resolves the new pod for the same selector (or the same pod name if retained)
    And a new port-forward tunnel is established to the resolved pod
    And the tunnel state transitions to "Active"
    And the UI shows the new tunnel as "Active — nginx-def456 :8080 → :80"

  @chaos @network
  Scenario: Disconnected tunnel does not block other active tunnels
    Given tunnel "T1" is "Disconnected" due to pod restart
    And tunnel "T2" is "Active": local :9090 → pod "redis-xyz" :6379
    When the operator inspects the tunnel list
    Then tunnel "T2" continues to forward traffic without interruption
    And the metric "tunnel_active_count" equals 1 (only T2)
