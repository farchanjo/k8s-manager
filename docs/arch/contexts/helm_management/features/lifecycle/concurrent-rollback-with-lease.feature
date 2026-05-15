# DDD role: BehaviouralSpecification
# Bounded context: helm_management
# References: ADR-0011, ADR-0015

Feature: Concurrent rollback prevention via Kubernetes Lease
  As an operator
  I want only one rollback to proceed at a time for a given release
  So that concurrent rollbacks do not race-write conflicting revision Secrets

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And release "nginx" is at revision 5

  @race @lifecycle
  Scenario: Two operators initiate rollback simultaneously — one acquires Lease and proceeds
    Given operator A and operator B both initiate rollback to revision 4 at the same instant
    When both RollbackActors attempt to create or update Lease "helm-rollback-nginx"
    Then exactly one RollbackActor acquires the Lease (due to Kubernetes optimistic concurrency on the Lease object)
    And the winning actor proceeds with the SSA apply and revision Secret write
    And the losing actor receives a Lease conflict error
    And the losing actor surfaces the message "Another rollback is in progress for nginx — please wait and retry"
    And no duplicate revision Secret is written

  @race @lifecycle
  Scenario: Lease holder crashes mid-rollback — Lease expires and next operator can proceed
    Given operator A acquired the Lease and started applying manifests
    And operator A's K8sManager process is killed mid-rollback
    When the Lease's leaseDurationSeconds (e.g., 30 seconds) elapses
    Then the Lease is considered expired by the Kubernetes control plane
    And operator B can now acquire the Lease and retry the rollback from the beginning
    And the cluster may be in a partial-apply state; operator B is warned to verify cluster state

  @lifecycle @happy
  Scenario: Lease is released promptly after a successful rollback
    Given operator A acquires the Lease and completes the rollback successfully
    When the new revision Secret is written with status "deployed"
    Then the RollbackActor deletes the Lease object immediately
    And within 1 second of rollback completion, the Lease is gone from the cluster
    And no other rollback operations are blocked after this point

  @failure @lifecycle
  Scenario: Operator explicitly aborts rollback after Lease acquisition — Lease is released
    Given operator A has acquired the Lease and the confirmation modal is still open
    When operator A presses "Cancel" before the SSA starts
    Then the RollbackActor releases the Lease without applying any manifests
    And an audit entry is written with outcome "cancelled"
    And the Lease is deleted promptly
