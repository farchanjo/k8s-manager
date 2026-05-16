# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (FAB orchestration), ValueObject (KindSkeletonTemplate)
# Context: resource_browser
# Related ADRs: ADR-0066 (Floating action button for resource creation), ADR-0064 (Inline docked YAML editor pane), ADR-0030 (Integrated editor)
Feature: Resource list floating action button

  Background:
    Given the operator has a connected cluster session
    And a namespace "default" is active

  Scenario: FAB is visible on a workloads list pane
    Given the operator opens the Deployments list tab for namespace "default"
    When the list pane renders
    Then a circular floating action button is visible at the bottom-right of the list pane
    And the button has diameter 56pt and an accentBrand background
    And the button accessibility label is "Create Deployment"

  Scenario: FAB is hidden on the Nodes list pane
    Given the operator opens the Nodes list tab
    When the list pane renders
    Then no floating action button is present in the list pane
    And the keyboard shortcut Command+N has no effect while the Nodes list pane is focused

  Scenario: Create from scratch opens the kind skeleton in the inline editor
    Given the operator is viewing the Deployments list pane
    And the floating action button is visible
    When the operator clicks the floating action button
    Then a popover appears with three items: "Create from scratch", "Paste from clipboard", and "Fork from selected"
    When the operator selects "Create from scratch"
    Then the inline docked YAML editor opens in edit mode
    And the editor content is the Deployment skeleton template
    And the skeleton template contains the placeholder values "<name>", "<namespace>", and "<image>"
    And the real-time validation pipeline marks placeholder values as schema warnings

  Scenario: Paste from clipboard parses and pre-fills the inline editor
    Given the operator is viewing the ConfigMaps list pane
    And the system clipboard contains a valid YAML manifest for kind ConfigMap
    When the operator clicks the floating action button
    And selects "Paste from clipboard"
    Then the inline docked YAML editor opens in edit mode
    And the editor content matches the YAML content from the clipboard
    And the real-time validation pipeline runs against the pasted content

  Scenario: Fork from selected deep-copies the resource and resets create-unsafe metadata
    Given the operator is viewing the Deployments list pane
    And the operator has selected the row for a Deployment named "web-api"
    When the operator clicks the floating action button
    And selects "Fork from selected"
    Then the inline docked YAML editor opens in edit mode
    And the editor content contains "name: web-api-copy"
    And the editor content does not contain a "uid" field under metadata
    And the editor content does not contain a "resourceVersion" field under metadata
    And the editor content does not contain a "managedFields" field under metadata
    And the editor content does not contain a "status" section
