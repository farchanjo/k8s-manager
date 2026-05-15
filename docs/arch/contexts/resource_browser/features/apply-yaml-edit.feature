# DDD role: Feature
# Bounded context: resource_browser
Feature: Apply YAML edits to cluster resources

  As an operator managing a Kubernetes cluster
  I want to edit a resource's YAML manifest and apply the changes
  So that I can update workload configuration without switching to kubectl
  With full visibility of what will change before the change is made

  Background:
    Given the application is running with a healthy cluster connection
    And the operator has selected cluster "staging-cluster" as the active context
    And the detail panel is open for the resource under test

  Scenario: Edit ConfigMap and see diff preview before apply
    Given the detail panel is open for ConfigMap "app-config" in namespace "default"
    And the YAML editor shows the current manifest
    When the operator changes the value of key "LOG_LEVEL" from "info" to "debug"
    And the operator presses "Preview Changes"
    Then a diff preview panel appears showing one removed line and one added line
    And the removed line shows "LOG_LEVEL: info" in red
    And the added line shows "LOG_LEVEL: debug" in green
    And unchanged lines are collapsed with a count indicator

  Scenario: Server-side apply succeeds and list row is refreshed
    Given the detail panel is open for Deployment "api-server" in namespace "apps"
    And the operator has modified the YAML to set replicas from 2 to 4
    And the diff preview shows exactly one changed line under spec.replicas
    When the operator presses "Apply" in the confirmation modal
    Then the resource_browser context constructs an #ApplyYAML command with
      fieldManager "com.archanjo.K8sManager" and forceConflicts false
    And the command is evaluated by the mutation guard policy and allowed
    And the PATCH request is dispatched to the cluster with
      Content-Type "application/apply-patch+yaml"
    And the API server returns HTTP 200
    And the list view row for "api-server" shows "4/4" in the status column
    And an audit entry with outcome "succeeded" is written to cluster_mutation_audit

  Scenario: Ownership conflict surfaces force-ownership toggle
    Given the detail panel is open for Deployment "managed-app" in namespace "prod"
    And the field "spec.replicas" is currently owned by field manager "argo-cd"
    When the operator edits "spec.replicas" from 3 to 5 and presses "Preview Changes"
    And the operator presses "Apply" in the confirmation modal
    Then the API server returns HTTP 409 with a conflict message referencing "spec.replicas"
    And the diff preview modal re-appears showing the conflict details
    And a "Force ownership — take over conflicting fields" toggle is visible with a warning label
    When the operator enables the force-ownership toggle
    And presses "Apply (Force)"
    Then the PATCH request is re-dispatched with force=true in the query string
    And the API server returns HTTP 200
    And the list view row for "managed-app" shows "5/5" in the status column

  Scenario: Schema validation error from API server is surfaced inline
    Given the detail panel is open for Deployment "bad-deploy" in namespace "default"
    And the operator has entered an invalid YAML value for "spec.progressDeadlineSeconds"
      (value is "abc" instead of an integer)
    When the operator presses "Apply" in the confirmation modal
    Then the API server returns HTTP 422 with an error body referencing the invalid field
    And the diff preview modal re-appears with an inline error message
    And the error message shows the path "spec.progressDeadlineSeconds" and reason "Invalid value"
    And no audit entry with outcome "succeeded" is written

  Scenario: Cancel in diff preview modal produces no API call
    Given the detail panel is open for ConfigMap "feature-flags" in namespace "default"
    And the operator has modified "ENABLE_BETA" from "false" to "true"
    And the diff preview modal is showing the one-line change
    When the operator presses "Cancel"
    Then the diff preview modal is dismissed
    And no Kubernetes API call is dispatched
    And the YAML editor reverts to the original manifest
    And an audit entry with outcome "cancelled" is written to cluster_mutation_audit

  Scenario: Audit entry is persisted before the API call is dispatched
    Given the detail panel is open for Service "frontend" in namespace "web"
    And the operator has modified a port entry and pressed "Apply" in the confirmation modal
    When the resource_browser domain service constructs the #ApplyYAML command
    Then an audit entry with outcome "succeeded" is written to cluster_mutation_audit
      before the PATCH request leaves the application
    And if a network error occurs immediately after, the audit entry is already persisted
    And the audit entry carries the manifestDigest matching the SHA-256 of the sent YAML
