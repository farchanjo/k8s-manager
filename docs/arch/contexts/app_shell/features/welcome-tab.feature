# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (welcome tab orchestration), ReadModel (welcome action catalogue)
# Context: app_shell
# Related ADRs: ADR-0054 (Welcome tab and cluster-acquisition entry surface), ADR-0050 (Resource navigation taxonomy)
Feature: Welcome tab and cluster-acquisition entry surface

  Background:
    Given the application workspace is initialised
    And the "OpenTabsActor" manages the workspace tab list

  Scenario: Welcome tab opens on first launch before the onboarding overlay
    Given the operator launches K8sManager for the first time
    And onboarding state is "notStarted"
    When the application window is shown
    Then a tab with kind "welcome" and title "Welcome" exists in the tab bar at position 0
    And the Welcome tab is the active tab
    And the first-launch onboarding overlay is presented above the Welcome tab content

  Scenario: Welcome tab survives application restart
    Given the operator has completed the first-launch onboarding tour
    And the Welcome tab exists in the persisted tab state
    When the operator quits and relaunches K8sManager
    Then a tab with kind "welcome" and title "Welcome" exists in the tab bar at position 0
    And the Welcome tab carries no close button in the tab bar

  Scenario: Welcome tab reopens via command palette after navigating away
    Given the Welcome tab exists in the workspace
    And the operator has activated a different tab
    And the Welcome tab is not the active tab
    When the operator opens the command palette
    And the operator activates the "Go to Welcome tab" command
    Then the Welcome tab becomes the active tab
    And no second tab with kind "welcome" is created

  Scenario: Five canonical start actions are visible in the Welcome tab
    Given the Welcome tab is the active tab
    When the Welcome tab content is rendered
    Then an action tile labelled "Open Onboarding Wizard" is visible and keyboard-focusable
    And an action tile labelled "Add Kubeconfig from Clipboard" is visible and keyboard-focusable
    And an action tile labelled "Add Kubeconfig from File" is visible and keyboard-focusable
    And an action tile labelled "Add Clusters from AWS" is visible and keyboard-focusable
    And an action tile labelled "Add Clusters from AKS" is visible and keyboard-focusable
    And a "Useful Guides" section is visible below the action tiles

  Scenario: Escape key moves focus within the Welcome tab content and does not close the tab
    Given the Welcome tab is the active tab
    And the operator has keyboard focus inside the Welcome tab content area
    When the operator presses Escape
    Then the Welcome tab remains open and active
    And no tab is closed
    And keyboard focus returns to the first focusable element in the Welcome tab content area
