# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (action dispatch), ValueObject (RowAction)
# Context: resource_browser
# Related ADRs: ADR-0061 (Per-row resource action menu uniform shape), ADR-0012 (Mutating operations policy), ADR-0050 (Resource navigation taxonomy)
Feature: Per-row resource action menu uniform shape
  As a Kubernetes operator
  I want every resource list view to expose a consistent 3-dot action menu per row
  So that I can invoke Edit YAML, Delete, View Events, Copy Resource Link, Save YAML,
  and kind-specific actions without discovering which actions are available for each kind

  Background:
    Given the application is running on macOS 14 or later
    And the operator has an active session for cluster "prod-aks"
    And the operator has write permissions for the active namespace

  Scenario: Workloads family menu shape for a Deployment row
    Given the operator is viewing the Deployments list for namespace "production"
    When the operator opens the 3-dot action menu for Deployment "api-server"
    Then the menu contains the following items in order:
      | item               | accelerator |
      | Edit YAML          | E           |
      | View Events        | V           |
      | Copy Resource Link | Cmd-C       |
      | Save YAML          | Y           |
      | Delete             | X           |
      | Scale              | S           |
      | Rollout Restart    | R           |
    And the menu does not contain "View Logs"
    And the menu does not contain "Open Terminal"

  Scenario: Config family menu shape for a ConfigMap row
    Given the operator is viewing the ConfigMaps list for namespace "default"
    When the operator opens the 3-dot action menu for ConfigMap "app-config"
    Then the menu contains the following items in order:
      | item               | accelerator |
      | Edit YAML          | E           |
      | View Events        | V           |
      | Copy Resource Link | Cmd-C       |
      | Save YAML          | Y           |
      | Delete             | X           |
    And the menu does not contain "Scale"
    And the menu does not contain "Rollout Restart"
    And the menu does not contain "View Logs"
    And the menu does not contain "Open Terminal"
    And the menu does not contain "Port Forward"
    And the menu does not contain "View Subjects"

  Scenario: Delete action in the row menu triggers the ADR-0012 double-confirm flow
    Given the operator is viewing the Deployments list for namespace "production"
    And the operator opens the 3-dot action menu for Deployment "api-server"
    When the operator selects "Delete" (accelerator X)
    Then a first confirmation dialog appears with heading "Delete Deployment api-server?"
    And the operator must type "api-server" in the resource name field before the action button is enabled
    When the operator types "api-server" and clicks "Confirm"
    Then a second confirmation dialog appears with heading "This action cannot be undone. Delete api-server permanently?"
    When the operator clicks "Delete permanently"
    Then a DELETE request is dispatched to the Kubernetes API for Deployment "api-server"
    And an audit entry is written to cluster_mutation_audit with outcome "succeeded"
    And Deployment "api-server" is removed from the list on the next watch event

  Scenario: Keyboard accelerator dispatches the corresponding action
    Given the operator is viewing the Pods list for namespace "production"
    And the operator opens the 3-dot action menu for Pod "backend-xyz"
    When the operator presses the key "L"
    Then the Logs view opens for Pod "backend-xyz"
    And the action menu is dismissed

  Scenario: Menu hides actions that are incompatible with the kind within a family
    Given the operator is viewing the Pods list for namespace "production"
    When the operator opens the 3-dot action menu for Pod "backend-xyz"
    Then the menu contains "View Logs" (accelerator L)
    And the menu contains "Open Terminal" (accelerator T)
    And the menu does not contain "Scale"
    And the menu does not contain "Rollout Restart"
    Given the operator is viewing the StatefulSets list for namespace "production"
    When the operator opens the 3-dot action menu for StatefulSet "postgres"
    Then the menu contains "Scale" (accelerator S)
    And the menu contains "Rollout Restart" (accelerator R)
    And the menu does not contain "View Logs"
    And the menu does not contain "Open Terminal"
