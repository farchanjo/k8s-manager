# DDD role: BehaviouralSpecification
# Bounded context: helm_management
# References: ADR-0011, ADR-0012, ADR-0015
# CUE schema: contexts/helm_management/schemas/release.cue

Feature: Helm rollback happy path — Lease acquisition, SSA apply, new Secret written
  As an operator
  I want to roll back a Helm release to a previous revision safely
  So that I can recover from a failed deployment without using the helm CLI

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And release "nginx" is at revision 5 (status "deployed")
    And revision 4 (the target rollback) has status "superseded" and its manifests are stored in the Secret

  @happy @lifecycle
  Scenario: Successful rollback to revision 4 acquires Lease, applies manifests, writes new Secret
    Given the operator initiates rollback to revision 4 via the double-confirm modal
    And the confirmationToken is valid (within 300s window)
    When the operator confirms via the double-confirm flow
    Then the RollbackActor acquires a Kubernetes Lease "helm-rollback-nginx" in namespace "production"
    And the Lease prevents any other concurrent rollback from proceeding
    And the adapter applies each manifest from revision 4 via Server-Side Apply (SSA) with fieldManager "com.archanjo.K8sManager"
    And a new revision Secret "sh.helm.release.v1.nginx.v6" is written with status "deployed"
    And the previous revision 5 Secret is updated to status "superseded"
    And the Lease is released after the new Secret is written
    And an audit entry is written with verb "rollback" and outcome "succeeded"
    And the helm_management release list shows "nginx" at revision 6 with status "deployed"

  @failure @lifecycle
  Scenario: Rollback aborted when required Lease is already held
    Given another process holds the Lease "helm-rollback-nginx" with a valid leaseDurationSeconds
    When the operator attempts to rollback "nginx" to revision 4
    Then the RollbackActor fails to acquire the Lease
    And the rollback is aborted with the message "Another rollback is in progress for nginx — please wait"
    And no SSA requests are dispatched
    And no new revision Secret is written

  @happy @lifecycle
  Scenario: Rollback confirmation requires double-confirm as per ADR-0012
    When the operator selects rollback to revision 4
    Then the first confirmation modal shows the revision to be rolled back to and the number of manifests
    And the second confirmation requires typing the release name "nginx"
    When the operator types "nginx" and confirms
    Then the rollback proceeds to Lease acquisition
