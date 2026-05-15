# DDD role: Feature
# Bounded context: resource_browser
Feature: Scale workloads and trigger rollout restarts

  As an operator managing Kubernetes workloads
  I want to scale replica counts and trigger rollout restarts from the UI
  So that I can respond to load changes and push rolling updates
  Without leaving the application

  Background:
    Given the application is running with a healthy cluster connection
    And the operator has selected cluster "prod-cluster" as the active context
    And the resource browser sidebar shows the "apps/v1" section

  Scenario: Scale a Deployment from current replicas to a new count
    Given the resource list shows Deployment "web-frontend" in namespace "production"
    And "web-frontend" currently has 2 replicas as shown in the status column
    When the operator right-clicks the row and selects "Scale..."
    Then a scale popover appears showing current replicas "2"
    And the operator changes the value to "5"
    When the operator presses "Scale" in the popover
    Then a confirmation modal appears stating
      "Scale web-frontend from 2 to 5 replicas in production"
    When the operator presses "Confirm Scale"
    Then the resource_browser context constructs a #ScaleReplicas command
      with desiredReplicas 5
    And the command is evaluated by the mutation guard policy and allowed
    And a PATCH request is dispatched to the /scale subresource
    And the API server returns HTTP 200
    And the status column for "web-frontend" updates to show "5/5" within 5 seconds
    And an audit entry with outcome "succeeded" is written to cluster_mutation_audit

  Scenario: Scale a Deployment to zero suspends it
    Given the resource list shows Deployment "batch-processor" in namespace "jobs"
    And "batch-processor" currently has 3 replicas
    When the operator opens the scale popover and enters "0"
    And presses "Confirm Scale"
    Then a #ScaleReplicas command with desiredReplicas 0 is dispatched
    And the status column for "batch-processor" updates to show "0/0"
    And the detail panel shows a banner "Deployment scaled to zero — no pods are running"

  Scenario: Rollout restart Deployment triggers a rolling pod replacement
    Given the detail panel is open for Deployment "payment-api" in namespace "billing"
    And the toolbar shows a "Restart" button
    When the operator presses "Restart"
    Then a confirmation modal appears stating
      "Trigger a rolling restart of payment-api in billing"
    When the operator presses "Confirm Restart"
    Then the resource_browser context constructs a #RolloutRestart command
      with restartedAt set to the current RFC3339 timestamp
    And a PATCH request is dispatched to the Deployment's REST path
      injecting annotation "kubectl.kubernetes.io/restartedAt"
    And the API server returns HTTP 200
    And the Pod list for "payment-api" shows new pods being created within 10 seconds
    And an audit entry with outcome "succeeded" is written to cluster_mutation_audit

  Scenario: Rollout restart DaemonSet propagates to all nodes
    Given the detail panel is open for DaemonSet "node-exporter" in namespace "monitoring"
    When the operator presses "Restart" and confirms
    Then a #RolloutRestart command is dispatched for the DaemonSet
    And the API server returns HTTP 200
    And the status column for "node-exporter" shows a rolling update indicator
    And the Pod list for "node-exporter" shows pods being replaced one at a time

  Scenario: Cancel scale operation mid-flow produces no API call
    Given the scale popover is open for Deployment "auth-service" in namespace "platform"
    And the operator has entered "10" in the replica count field
    When the operator presses "Cancel" in the confirmation modal
    Then the confirmation modal is dismissed
    And no PATCH request to the /scale subresource is dispatched
    And the replica count shown in the list view remains unchanged
    And an audit entry with outcome "cancelled" is written to cluster_mutation_audit

  Scenario: Scale is rejected for a kind that does not support the scale subresource
    Given the resource list shows ConfigMap "shared-config" in namespace "default"
    When the operator attempts to invoke "Scale..." from the context menu
    Then the "Scale..." menu item is disabled
    And no scale popover appears
    And no API call is dispatched
