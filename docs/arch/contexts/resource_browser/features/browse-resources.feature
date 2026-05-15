# DDD role: Feature
# Bounded context: resource_browser
Feature: Browse Kubernetes resources by kind

  As an operator managing a Kubernetes cluster
  I want to browse resources by kind in the sidebar
  So that I can quickly inspect, filter, and navigate my workloads
  Without switching to kubectl or a web dashboard

  Background:
    Given the application is running with a healthy cluster connection
    And the operator has selected cluster "dev-cluster" as the active context
    And the resource browser sidebar is visible

  Scenario: List Pods in a namespace
    Given the operator selects kind "Pod" from the sidebar under "core/v1"
    And the operator selects namespace "default" from the namespace picker
    When the resource_browser context issues a list request for Pods in "default"
    Then the resource list view displays a row for each Pod in the "default" namespace
    And each row shows the pod name, status, age, and namespace columns
    And the status column reflects the current phase of each Pod ("Running", "Pending", "Failed", etc.)

  Scenario: Switch kind in sidebar preserves scroll position of previous kind
    Given the operator has scrolled the Deployment list to row 42
    And the list view shows "Deployment" resources in namespace "production"
    When the operator clicks "ConfigMap" in the sidebar
    Then the resource list view reloads and shows ConfigMaps in "production"
    When the operator clicks "Deployment" in the sidebar again
    Then the resource list view returns to the Deployment list
    And the scroll position is restored to row 42

  Scenario: Open YAML shows server-side manifest
    Given the resource list displays a ConfigMap named "app-config" in namespace "default"
    When the operator double-clicks the "app-config" row
    Then the detail panel opens and issues a GET request for the live manifest
    And the YAML editor panel displays the server-returned manifest converted to YAML
    And the manifest includes the full metadata including managedFields and resourceVersion

  Scenario: Inline label edit triggers confirmation before apply
    Given the detail panel is open for Deployment "nginx" in namespace "web"
    And the labels inspector panel is visible
    When the operator edits the value of label "app" from "nginx" to "nginx-v2"
    And the operator presses the checkmark button to confirm the inline edit
    Then a confirmation modal appears showing a diff of the labels change
    And the modal shows label "app" changed from "nginx" to "nginx-v2"
    When the operator presses "Apply Labels"
    Then the resource_browser context issues a #LabelPatch command
    And the confirmation modal is dismissed
    And the labels inspector panel reflects the new value "nginx-v2"

  Scenario: CRDs discovered dynamically appear in sidebar under their API group
    Given the cluster has a CustomResourceDefinition with group "argoproj.io" and kind "Application"
    When the resource browser completes its CRD discovery pass at connection time
    Then the sidebar contains a section "argoproj.io" under "Custom Resources"
    And "Application" appears as a selectable kind under "argoproj.io"
    When the operator clicks "Application"
    Then the resource list view issues a list request for "Application" instances
    And rows are displayed for each discovered "Application" resource in the selected namespace

  Scenario: Watch stream delivers incremental updates to the list view
    Given the operator is viewing the Pod list in namespace "default"
    And the resource_browser context has an active watch stream for Pods
    When a new Pod named "job-worker-7qxkp" is created on the cluster
    Then a new row for "job-worker-7qxkp" appears in the list view within 2 seconds
    And no full list refresh is triggered
    When the Pod "job-worker-7qxkp" is deleted from the cluster
    Then the row for "job-worker-7qxkp" is removed from the list view within 2 seconds

  Scenario: Secret values are redacted by default in the detail panel
    Given the resource list displays a Secret named "db-credentials" in namespace "default"
    When the operator opens the detail panel for "db-credentials"
    Then the YAML editor panel shows the Secret manifest
    And every value under the "data" key is replaced with the placeholder "[redacted]"
    When the operator presses the "Reveal" button next to the key "DB_PASSWORD"
    Then only the value for "DB_PASSWORD" is decoded and displayed
    And all other values remain redacted
