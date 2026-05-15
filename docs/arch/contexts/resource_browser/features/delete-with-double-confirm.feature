# DDD role: Feature
# Bounded context: resource_browser
Feature: Delete resources with double confirmation

  As an operator managing a Kubernetes cluster
  I want to delete resources through a double-confirmation flow
  So that I cannot accidentally destroy a running workload or namespace
  And so that every deletion is recorded in the audit log

  Background:
    Given the application is running with a healthy cluster connection
    And the operator has selected cluster "staging-cluster" as the active context
    And the resource browser sidebar is visible

  Scenario: Delete a Pod with default grace period
    Given the resource list shows Pod "crash-loop-pod" in namespace "default"
    When the operator right-clicks the row and selects "Delete..."
    Then the first confirmation modal appears with title "Delete Pod"
    And the modal shows "crash-loop-pod" in namespace "default"
    And a grace period field is pre-filled with the Kubernetes default (blank = use default)
    And a propagation policy selector shows "Background" selected by default
    When the operator presses "Continue to confirm"
    Then the second confirmation step appears
    And a text field with placeholder "Type the pod name to confirm" is visible
    When the operator types "crash-loop-pod" into the confirmation text field
    Then the "Delete" button becomes enabled
    When the operator presses "Delete"
    Then a #DeleteResource command is constructed with propagationPolicy "Background"
    And the command is evaluated by the mutation guard policy with doubleConfirmed true
    And the DELETE request is dispatched to the cluster
    And the API server returns HTTP 200
    And the row for "crash-loop-pod" is removed from the list view within 2 seconds
    And an audit entry with outcome "succeeded" is written to cluster_mutation_audit

  Scenario: Delete a Namespace with Foreground propagation waits for owned resources
    Given the resource list shows Namespace "experiment-alpha" at cluster scope
    When the operator initiates the delete flow for "experiment-alpha"
    And selects propagation policy "Foreground"
    And types "experiment-alpha" in the second confirmation step
    And presses "Delete"
    Then the DELETE request is dispatched with propagationPolicy "Foreground"
    And the Namespace row shows a "Terminating" status indicator
    And the UI continues refreshing the Namespace status via the watch stream
    And the row is removed from the list view once the Namespace reaches the "Terminating" phase
      and the finaliser list is empty

  Scenario: Double-confirm modal requires exact name match to enable Delete button
    Given the first confirmation modal is shown for Pod "api-worker-5g4z" in namespace "api"
    And the operator presses "Continue to confirm"
    When the operator types "api-worker" in the confirmation text field (partial name)
    Then the "Delete" button remains disabled
    When the operator types "-5g4z" to complete the name
    Then the "Delete" button becomes enabled

  Scenario: Cancel at the first confirmation modal produces no API call
    Given the resource list shows Deployment "legacy-monolith" in namespace "apps"
    When the operator opens the delete flow for "legacy-monolith"
    And the first confirmation modal is visible
    When the operator presses "Cancel"
    Then the modal is dismissed
    And no DELETE request is dispatched
    And an audit entry with outcome "cancelled" is written to cluster_mutation_audit

  Scenario: Cancel at the second confirmation step (name-input) produces no API call
    Given the first confirmation modal for Secret "old-api-key" has been accepted
    And the second confirmation step is visible with the name input field
    When the operator types "old-api-key" into the confirmation field
    And then presses "Cancel" instead of "Delete"
    Then the modal is dismissed
    And no DELETE request is dispatched
    And an audit entry with outcome "cancelled" is written to cluster_mutation_audit
    And the Secret row remains in the list view

  Scenario: Mutation guard denies delete when doubleConfirmed is absent
    Given a #DeleteResource command is submitted programmatically without doubleConfirmed set
    When the mutation guard policy evaluates the command
    Then the deny_reasons set contains the message about missing doubleConfirmed
    And the allow rule evaluates to false
    And no API call is dispatched
    And an audit entry with outcome "denied" is written to cluster_mutation_audit

  Scenario: Delete with custom grace period sends the specified seconds to the API server
    Given the first confirmation modal is shown for Pod "stuck-terminating" in namespace "ops"
    And the operator sets grace period to "0" seconds (immediate deletion)
    And the operator completes the double-confirm flow
    When the DELETE request is dispatched
    Then the request URL includes the query parameter "gracePeriodSeconds=0"
    And the audit entry records the gracePeriodSeconds value 0
