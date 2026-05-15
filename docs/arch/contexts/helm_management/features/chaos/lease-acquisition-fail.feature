# DDD role: ChaosScenario
# Bounded context: helm_management
# Failure mode: concurrent Helm operation lease conflict
# References: ADR-0041, ADR-0026, ADR-0030

Feature: Concurrent rollback attempt fails to acquire Lease and aborts with audit record
  As a cluster operator
  I need concurrent Helm rollback operations to be serialized via Lease acquisition
  So that only one rollback runs at a time and the losing instance is audited cleanly

  Background:
    Given release "my-app" at revision 5 is installed in namespace "production"
    And a Kubernetes Lease "helm-my-app-lock" exists in namespace "production"

  @chaos @concurrency
  Scenario: Second concurrent rollback fails to acquire Lease within 30 seconds
    Given the first rollback instance has acquired Lease "helm-my-app-lock" and is in progress
    When a second rollback instance starts and attempts to acquire the same Lease
    Then the second instance polls the Lease for up to 30 seconds
    And after 30 seconds without acquisition it aborts
    And an audit entry is written with operation "rollback-aborted-concurrent" for release "my-app"
    And the UI shows the second rollback as "Aborted — concurrent rollback in progress"

  @chaos @concurrency
  Scenario: First rollback completes and releases Lease before the 30-second window
    Given the first rollback instance completes in 15 seconds and releases the Lease
    When the second rollback instance was waiting and the Lease is released at 15 seconds
    Then the second instance acquires the Lease after the first releases it
    And the second rollback proceeds normally
    And no "rollback-aborted-concurrent" audit entry is written for the second instance

  @chaos @concurrency
  Scenario: Lease is not left held when a rollback aborts due to timeout
    Given a rollback instance held the Lease and then crashed (simulated)
    When the Lease TTL expires (configured at 60 seconds)
    Then the expired Lease is not renewed
    And a subsequent rollback instance can acquire the Lease after TTL expiry
    And no stuck-lease alert is surfaced to the operator
