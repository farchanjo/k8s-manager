# DDD role: ChaosScenario
# Bounded context: port_forwarding
# Failure mode: cascade (cluster session close tears down all tunnels for that cluster)
# References: ADR-0041, ADR-0025, ADR-0028

Feature: Cluster session close cascades to tear down all associated port-forward tunnels
  As a cluster operator
  I need all port-forward tunnels to be torn down when their parent cluster session closes
  So that no orphaned connections linger silently after the session ends

  Background:
    Given cluster session "prod-eu" is "Connected"
    And 5 port-forward tunnels are active under session "prod-eu":
      | Tunnel | Local Port | Target Pod           | Target Port |
      | T1     | 8080       | nginx-abc            | 80          |
      | T2     | 8443       | nginx-abc            | 443         |
      | T3     | 5432       | postgres-primary     | 5432        |
      | T4     | 6379       | redis-cache          | 6379        |
      | T5     | 9090       | prometheus-server    | 9090        |

  @chaos @network
  Scenario: Closing the cluster session tears down all 5 tunnels within 5 seconds
    When the cluster session "prod-eu" is closed (operator action or API-server unreachable timeout)
    Then all 5 tunnels (T1–T5) are torn down within 5 seconds
    And each tunnel transitions to state "Disconnected" with reason "cluster-session-closed"
    And no tunnel retains an open TCP listener on its local port
    And the metric "tunnel_active_count" for cluster "prod-eu" equals 0

  @chaos @network
  Scenario: Cascaded tunnel teardown emits an event per tunnel for observability
    When the cluster session "prod-eu" closes
    Then 5 "TunnelDisconnected" events are emitted, one per tunnel
    And each event carries the tunnel ID and reason "cluster-session-closed"
    And the events are recorded in telemetry within the 5-second window

  @chaos @network
  Scenario: Tunnels for other cluster sessions are unaffected by the cascade
    Given cluster session "staging-us" has 2 active tunnels (T6, T7)
    When cluster session "prod-eu" closes and cascades teardown of T1–T5
    Then tunnels T6 and T7 remain in state "Active"
    And no teardown event is emitted for T6 or T7
