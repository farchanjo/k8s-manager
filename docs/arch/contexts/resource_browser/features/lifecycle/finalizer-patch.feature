# DDD role: BehaviouralSpecification
# Bounded context: resource_browser
# References: ADR-0012
# CUE schema: contexts/resource_browser/schemas/mutation_audit_entry.cue

Feature: Finalizer patch — removing a stuck resource's finalizer
  As an operator
  I want to remove finalizers from stuck resources using a dedicated destructive action
  So that blocked resources can be unblocked with a proper audit trail

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Namespace "abandoned" is stuck in "Terminating" with finalizer "kubernetes"

  @happy @lifecycle
  Scenario: Finalizer patch requires double-confirm and is logged as destructive
    Given the operator selects "abandoned" and chooses "Remove Finalizer" from the contextual actions
    When the double-confirm modal appears listing the finalizer "kubernetes" to be removed
    And the operator types "abandoned" in the confirmation field and presses the action button
    Then a strategic merge PATCH is dispatched targeting "metadata.finalizers" with an empty array
    And the audit entry has verb "finalizer-patch" and outcome "succeeded"
    And the Namespace transitions from "Terminating" to deleted within the cluster

  @failure @lifecycle
  Scenario: Finalizer patch aborted at first confirmation
    Given the operator selects "abandoned" and chooses "Remove Finalizer"
    When the first confirmation modal appears with a warning about orphaned external resources
    And the operator presses "Cancel"
    Then no PATCH is dispatched to the API server
    And an audit entry is written with outcome "cancelled" and verb "finalizer-patch"

  @security @lifecycle
  Scenario: Finalizer patch on a resource not in the mutation allowlist is denied by policy
    Given the "cluster_mutation_audit" policy does NOT list "PersistentVolume" finalizer-patch as allowed
    When the operator attempts to remove a finalizer from a PersistentVolume via the context menu
    Then the MutationGuardPort denies the command
    And a toast shows "finalizer-patch not permitted for PersistentVolume — contact cluster admin"
    And no PATCH is dispatched

  @lifecycle @happy
  Scenario: Multiple finalizers — modal lists all finalizers to be removed
    Given a Pod "orphan-0" has finalizers ["owner.io/gc", "protect.io/safety"]
    When the operator chooses "Remove Finalizer" for "orphan-0"
    Then the double-confirm modal lists both finalizers explicitly
    And the warning states "Removing these finalizers may orphan associated external resources"
    And after double-confirm both finalizers are removed in a single PATCH
