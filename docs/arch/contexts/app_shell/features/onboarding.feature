# DDD Role: ApplicationService (first-launch orchestration), ReadModel (onboarding state)
# Context: app_shell
# Related ADRs: ADR-0021 (design system), ADR-0023 (command palette and shortcuts), ADR-0012 (mutating operations policy)
Feature: Operator onboarding

  Background:
    Given the application has no persisted onboarding state
    And no kubeconfig files are present on disk

  Scenario: First-launch tour — three-step welcome sequence
    Given the operator launches K8sManager for the first time
    When the welcome overlay is presented
    Then step 1 of 3 is visible with heading "Welcome to K8sManager"
    And a "Next" button advances to step 2 with heading "Import your kubeconfig"
    And confirming the path in step 2 advances to step 3 with heading "Try the AI assistant"
    And completing step 3 dismisses the overlay and persists onboarding state as complete

  Scenario: Operator skips the first-launch tour via keyboard shortcut
    Given the welcome overlay is presented at step 1
    When the operator presses Escape
    Then the overlay is dismissed immediately
    And onboarding state is persisted as skipped
    And the main window is shown without completing the tour

  Scenario: Empty cluster state shows action hint for first cluster
    Given onboarding is complete
    And the sidebar cluster list is empty
    When the content area is rendered
    Then an empty state view is shown with the label "Configure your first cluster"
    And an action button "Add cluster" is visible and keyboard-focusable

  Scenario: No kubeconfig detected — path picker is presented
    Given the operator is at step 2 of the first-launch tour
    And no kubeconfig file is found at the default paths
    When step 2 is rendered
    Then a file-path picker control is visible with placeholder "Select kubeconfig file"
    And a "Browse…" button opens the macOS open-file panel filtered to YAML and JSON files

  Scenario: First LLM API key added displays try-a-prompt CTA
    Given onboarding is complete
    And no LLM provider profile exists
    When the operator saves a new provider profile with a valid API key
    Then a contextual call-to-action overlay appears with the label "Try a prompt"
    And activating the CTA opens the assistant chat panel with an example prompt pre-filled

  Scenario: First mutating operation prompts operator to confirm understanding of ADR-0012
    Given onboarding is complete
    And the operator has never performed a mutating operation
    When the operator initiates a mutating operation for the first time
    Then a modal is presented explaining the mutation safety policy
    And the modal references that mutations require explicit confirmation per the application policy
    And the operator must acknowledge by pressing "I understand" before the mutation flow continues
    And subsequent mutating operations do not present this modal again

  Scenario: Resume tour accessible from settings
    Given onboarding state is persisted as skipped or complete
    When the operator opens Settings and navigates to the General section
    Then a "Restart onboarding tour" button is visible
    And activating the button resets onboarding state and presents the welcome overlay at step 1
