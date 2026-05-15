# DDD role: BehaviouralSpecification
# Bounded context: helm_management
# References: ADR-0012, ADR-0015

Feature: Helm rollback aborted when target revision references an uninstalled CRD
  As an operator
  I want rollback to fail fast and cleanly when a required CRD is missing
  So that partial applies do not leave the cluster in an inconsistent state

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And release "prometheus-stack" is at revision 10 (status "deployed")
    And the rollback target is revision 7
    And revision 7's manifests include a CustomResource "PrometheusRule" that requires a CRD uninstalled since then

  @failure @lifecycle
  Scenario: SSA fails on first manifest referencing a missing CRD — rollback aborted
    Given the operator has confirmed the rollback via the double-confirm modal
    And the RollbackActor has acquired the Lease "helm-rollback-prometheus-stack"
    When the adapter attempts to SSA the first manifest referencing "monitoring.coreos.com/v1/PrometheusRule"
    Then the API server returns HTTP 404 "no kind PrometheusRule is registered" or similar
    And the RollbackActor immediately aborts the rollback
    And no further manifests from revision 7 are applied
    And the new revision Secret "sh.helm.release.v1.prometheus-stack.v11" is NOT written
    And the current revision 10 Secret remains at status "deployed" (unchanged)
    And the Lease is released
    And an audit entry is written with verb "rollback", outcome "failed", and reason "missing-crd"

  @failure @lifecycle
  Scenario: Audit entry "rollback-aborted" is written before the Lease is released
    Given the SSA failure has been detected
    When the RollbackActor writes the audit entry and then releases the Lease
    Then the audit entry exists in "cluster_mutation_audit" before the Lease object is deleted
    And the audit entry contains the list of manifests that were not applied

  @happy @lifecycle
  Scenario: Rollback to a revision with no CRD dependencies succeeds
    Given revision 6 of "prometheus-stack" contains no CRD manifests or CustomResource objects
    When the operator initiates rollback to revision 6 and confirms
    Then all manifests from revision 6 are applied via SSA without CRD errors
    And a new revision Secret at version 11 is written with status "deployed"
    And the audit entry has outcome "succeeded"

  @failure @lifecycle
  Scenario: Partial SSA success followed by failure leaves cluster in partial state — operator is warned
    Given manifests 1 through 3 of revision 7 apply successfully via SSA
    And manifest 4 fails due to a missing CRD
    When the RollbackActor aborts
    Then the UI shows a warning: "Rollback partially applied — manifests 1-3 were updated but manifest 4 failed. Check cluster state before retrying."
    And the audit entry records partialApplyCount = 3
