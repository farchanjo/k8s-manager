# DDD role: ChaosScenario
# Bounded context: helm_management
# Failure mode: partial Server-Side Apply failure during rollback
# References: ADR-0041, ADR-0030

Feature: Partial SSA failure mid-rollback aborts entire rollback atomically
  As a cluster operator
  I need a Helm rollback to abort completely if any manifest in the set fails SSA
  So that the release never ends up in a half-rolled-back state

  Background:
    Given release "payment-service" is at revision 8 (broken) in namespace "payments"
    And revision 7 contains 7 manifests: 1 Deployment, 2 Services, 2 ConfigMaps, 1 Secret, 1 HPA
    And the rollback operator has acquired the Lease and begun applying revision 7

  @chaos @concurrency
  Scenario: Manifest 3 of 7 fails SSA and the entire rollback is aborted
    Given manifests 1 and 2 of 7 have been applied successfully via SSA
    When manifest 3 (a ConfigMap) fails SSA with "field manager conflict"
    Then the rollback controller aborts immediately without applying manifests 4–7
    And no new Helm Secret is written for a revision 9
    And the current Helm Secret for revision 8 remains intact and unmodified
    And an audit entry is written with operation "rollback-aborted-partial-failure" for release "payment-service"

  @chaos @concurrency
  Scenario: UI shows partial rollback failure and preserves ability to retry
    Given the rollback aborted at manifest 3 of 7
    When the operator views the release status panel
    Then the UI displays "Rollback failed — applied 2/7 manifests before abort"
    And the release status in the UI reflects revision 8 (unchanged)
    And the operator can attempt the rollback again without any manual cleanup

  @chaos @concurrency
  Scenario: Manifests applied before the failure are NOT rolled back by the abort
    Given manifests 1 and 2 were applied successfully before the abort
    When the rollback aborts at manifest 3
    Then the cluster state for manifests 1 and 2 reflects the partially-applied revision 7 values
    And this partial state is surfaced in the audit trail as "partially applied before abort"
    And the operator is advised to verify those two resources manually
