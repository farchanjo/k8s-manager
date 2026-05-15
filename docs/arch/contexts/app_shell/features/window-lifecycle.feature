# DDD role: Feature
# Bounded context: app_shell
Feature: Application window lifecycle

  As an operator on macOS
  I want K8sManager to behave like a first-class macOS application
  So that it integrates cleanly with my window-management and login workflow

  Background:
    Given the application is installed as a Developer ID signed bundle
    And the operator has launched the application at least once

  Scenario: Cold launch restores the last-used context
    Given the most recent application run ended with active context "staging"
    And "staging" is still declared in the operator's current kubeconfig
    When the operator launches the application
    Then the main window appears within two seconds on a clean macOS 14 host
    And the active context is "staging"
    And the selectedBy field is "restored"

  Scenario: Cold launch with a kubeconfig that no longer holds the last-used context
    Given the most recent application run ended with active context "old-prod"
    And "old-prod" is no longer declared in the operator's current kubeconfig
    When the operator launches the application
    Then the application falls back to the kubeconfig-level current-context
    And a non-blocking banner explains why the fallback occurred

  Scenario: Closing the main window does not quit the application
    Given the main window is visible
    When the operator presses Command-W
    Then the main window closes
    And the application remains running, with the menu bar active

  Scenario: Reopening the application from the Dock restores the main window
    Given the application is running with the main window closed
    When the operator activates the application from the Dock
    Then the main window is restored to its previous frame
    And the active context is unchanged

  Scenario: Quitting the application persists state
    Given the active context is "dev"
    And two contexts are pinned
    When the operator quits the application
    Then the last-used context "dev" is persisted
    And the two pinned contexts are persisted
    And no credential material is persisted
