# DDD role: BehaviouralSpecification
@adr-0051 @adr-0012
Feature: Detail drawer toolbar actions
  As a Kubernetes operator
  I want a slide-in detail drawer to appear when I select a resource in the tab content area
  So that I can inspect resource properties, view live metrics, and perform common actions
  Without leaving the current tab or navigating to a separate view

  Background:
    Given the application is running on macOS 14 or later
    And the operator has an active session for cluster "prod-aks"
    And Prometheus is configured and reachable for cluster "prod-aks"
    And the operator has write permissions for the active namespace

  Scenario: Selecting a resource row opens the detail drawer
    Given the operator is viewing the Deployments tab for namespace "production"
    When the operator clicks the "api-server" deployment row
    Then the detail drawer slides in from the right edge of the content area
    And the drawer header shows: kind badge "DEP", name "api-server", namespace "production"
    And the drawer shows the action toolbar with available actions
    And the drawer shows the Prometheus metrics panel with CPU and memory sparklines

  Scenario: Detail drawer shows only permitted actions per kind
    Given the detail drawer is closed
    When the operator opens the detail drawer for a ConfigMap "app-config"
    Then the action toolbar shows: "Edit YAML", "Delete"
    And the action toolbar does not show: "Rollout Restart", "Scale", "Logs"

  Scenario: Detail drawer for a Pod shows Logs action
    Given the detail drawer is closed
    When the operator opens the detail drawer for Pod "backend-xyz" in namespace "default"
    Then the action toolbar shows: "Edit YAML", "Delete", "Logs"
    And the containers section shows container list with status, image, restart count
    And the volumes section shows volume list with mount paths

  Scenario: Edit YAML action opens the integrated editor with the resource manifest
    Given the detail drawer is open for Deployment "api-server"
    When the operator clicks "Edit YAML" in the action toolbar
    Then the integrated editor opens with the YAML representation of "api-server"
    And the editor supports realtime dry-run apply and diff preview per ADR-0030
    And the editor uses server-side apply with field manager "com.archanjo.K8sManager"

  Scenario: Rollout Restart action is available for Deployment, StatefulSet, DaemonSet
    Given the detail drawer is open for Deployment "api-server"
    Then the action toolbar includes "Rollout Restart"
    When the operator clicks "Rollout Restart"
    Then the mutation guard (ADR-0012) is consulted and allows the operation
    And a confirmation dialog appears: "Restart api-server?"
    When the operator confirms
    Then a rollout restart PATCH is issued to the Kubernetes API
    And a MutationApplied domain event is emitted

  Scenario: Delete action requires double-confirm per ADR-0012
    Given the detail drawer is open for Pod "crashed-pod" in namespace "default"
    When the operator clicks "Delete"
    Then a first confirmation dialog appears: "Delete pod crashed-pod?"
    When the operator clicks "Confirm"
    Then a second confirmation dialog appears: "This action cannot be undone. Delete crashed-pod permanently?"
    When the operator clicks "Delete permanently"
    Then the delete request is issued to the Kubernetes API
    And the pod is removed from the resource list on the next watch event

  Scenario: Delete action for a pinned tab resource confirms with a warning
    Given a "Pods" tab is pinned and the detail drawer is open for a pod
    When the operator completes the double-confirm delete
    Then the pod is deleted
    And the pinned tab remains open, showing the updated (empty or refreshed) pod list

  Scenario: Scale action opens a scale dialog for Deployment and StatefulSet
    Given the detail drawer is open for Deployment "web-frontend" with 3 replicas
    When the operator clicks "Scale"
    Then a scale dialog appears showing current replicas: 3
    When the operator enters 5 and clicks "Apply Scale"
    Then a scale PATCH is issued to "web-frontend/scale" subresource
    And the deployment row updates to show 5 desired replicas on the next watch event

  Scenario: Prometheus metrics panel shows CPU and memory sparklines for a Pod
    Given the detail drawer is open for Pod "backend-xyz"
    And Prometheus has metrics for Pod "backend-xyz"
    When the metrics panel finishes loading
    Then the metrics panel shows a CPU usage sparkline (last 30 minutes)
    And a memory usage sparkline (last 30 minutes)
    And the sparklines auto-refresh every 30 seconds via metricsObservability

  Scenario: Metrics panel is hidden when Prometheus is not configured
    Given Prometheus is not configured for cluster "local-kind"
    When the operator opens the detail drawer for a Pod on "local-kind"
    Then the metrics panel section is absent from the detail drawer
    And no Prometheus-related error messages appear

  Scenario: Events section shows last 20 Kubernetes events for the resource
    Given the detail drawer is open for Deployment "api-server"
    When the events section is expanded
    Then the events section shows up to 20 events whose involvedObject is "api-server"
    And events are displayed in reverse chronological order (newest first)
    And events auto-refresh when new events arrive on the watch stream

  Scenario: Drawer width is persisted per kind across sessions
    Given the operator resizes the detail drawer to 480 pt while viewing a Deployment
    And the application is restarted
    When the operator opens the detail drawer for any Deployment
    Then the drawer opens at 480 pt width
    And the drawerWidth is stored in the DocumentTab's drawerWidth field

  Scenario: Keyboard shortcut Cmd-Shift-I toggles the detail drawer
    Given the operator is viewing the Pods tab with a pod selected
    When the operator presses Cmd-Shift-I
    Then the detail drawer opens
    When the operator presses Cmd-Shift-I again
    Then the detail drawer closes
    And the selected pod row remains highlighted in the content list
