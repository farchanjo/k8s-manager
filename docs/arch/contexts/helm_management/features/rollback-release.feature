# DDD role: Feature
# Bounded context: helm_management
Feature: Roll back a Helm release to a previous revision

  As an operator managing a Kubernetes cluster
  I want to roll back a deployed Helm release to a specific previous revision
  So that I can recover from a failed upgrade or unwanted configuration change
  without leaving K8sManager or running helm rollback from the CLI

  The rollback operation is mutating and is subject to ADR-0012 and ADR-0015:
  it requires a double-confirm modal, writes an audit entry before the API
  call is dispatched, applies the stored manifest via Server-Side Apply with
  field manager "com.archanjo.K8sManager", and creates a new revision Secret
  with revision number = current latest revision + 1.

  Background:
    Given the application is running with a healthy cluster connection
    And the operator has selected cluster "prod-cluster" as the active context
    And the detail view for release "prometheus" in namespace "monitoring" is open
    And the current latest revision is 7 with status "deployed"
    And revisions 1 through 6 exist with status "superseded"

  Scenario: Rollback to a previous revision creates a new revision numbered current + 1
    Given the operator selects revision 5 in the "History" tab
    And the operator clicks "Rollback to revision 5"
    And the operator confirms the first confirmation modal with the release name "prometheus"
    And the operator confirms the second confirmation modal by pressing "Confirm Rollback"
    When the RollbackOrchestrator executes the rollback to revision 5
    Then a new Kubernetes Secret named "sh.helm.release.v1.prometheus.v8" is created
    And the new Secret type is "helm.sh/release.v1" and label "owner=helm"
    And the new Secret's decoded release JSON has version 8, status "deployed"
    And the new Secret's manifestYAML field equals the manifestYAML from revision 5
    And the new Secret's info.description is "Rollback to 5"
    And the current revision in the releases panel updates to 8 with status "deployed"

  Scenario: Rollback requires a double-confirm modal before any API call is dispatched
    Given the operator selects revision 4 in the "History" tab
    And the operator clicks "Rollback to revision 4"
    When the first confirmation modal appears
    Then the first modal title is "Roll back prometheus?"
    And the first modal body describes that manifests from revision 4 will be re-applied
    And the first modal body shows a summary of the chart version from revision 4
    And the first modal has a "Cancel" button and a "Next" button
    When the operator presses "Next"
    Then a second confirmation modal appears with title "Confirm destructive action"
    And the second modal requires the operator to type the release name "prometheus" to enable the button
    When the operator types "prometheus" in the confirmation input field
    Then the "Confirm Rollback" button becomes enabled
    When the operator presses "Confirm Rollback"
    Then the rollback API call is dispatched
    And the audit entry for the rollback is written to the cluster_mutation_audit table
    And the audit entry commandKind is "#RollbackTo" with targetRevision 4

  Scenario: Rollback audit entry is written before the API call is dispatched
    Given the operator has confirmed the double-confirm modal for rolling back to revision 3
    When the RollbackOrchestrator begins executing the rollback
    Then an audit entry with outcome "pending" is written to the cluster_mutation_audit table
    And the audit entry contains the kubernetesContextId, namespace "monitoring", name "prometheus"
    And the audit entry commandKind is "#RollbackTo" and targetRevision is 3
    When the Kubernetes API call for Server-Side Apply completes successfully
    Then the audit entry outcome is updated to "succeeded"
    And the audit entry kubernetesStatusCode is 200 or 201

  Scenario: Rollback fails when the target revision Secret does not exist
    Given the release "prometheus" history shows revisions 1 through 7
    And revision 2's Secret "sh.helm.release.v1.prometheus.v2" has been manually deleted from the cluster
    When the operator attempts to roll back to revision 2
    Then the helm_management context fetches the Secret for revision 2 and finds it absent
    And the rollback operation is aborted before any confirmation modal is shown
    And an error message is displayed: "Revision 2 of prometheus is no longer available in the cluster."
    And no audit entry is written for the failed rollback attempt

  Scenario: Server-Side Apply is used to apply the rollback manifests
    Given the operator has confirmed rollback to revision 5 through both confirmation modals
    When the RollbackOrchestrator applies the manifests from revision 5 to the cluster
    Then the apply uses the Kubernetes PATCH endpoint with query parameter "fieldManager=com.archanjo.K8sManager"
    And the apply uses content-type "application/apply-patch+yaml" (Server-Side Apply)
    And the apply does NOT use client-side apply or the last-applied-configuration annotation
    And the apply processes each resource in the manifest YAML in document order
    And if the API server returns HTTP 409 (conflict), the operator is prompted to choose force-ownership or cancel
