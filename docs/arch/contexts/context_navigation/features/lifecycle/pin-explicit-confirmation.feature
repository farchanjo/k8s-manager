# DDD role: BehaviouralSpecification
# Bounded context: context_navigation
# References: ADR-0005, ADR-0023

Feature: Pinning a cluster requires an explicit operator action — no auto-pin
  As an operator
  I want clusters to be pinned only when I explicitly choose to pin them
  So that the pinned list reflects my deliberate choices and does not grow unexpectedly

  Background:
    Given the context navigator is visible with the operator's cluster list

  @happy @lifecycle
  Scenario: Pin via explicit button click is persisted
    Given "staging-eu-west" appears in the context navigator cluster list
    When the operator right-clicks (or long-presses) "staging-eu-west" and selects "Pin"
    Then a pinAction gesture is recorded with actionType="explicit-button-click"
    And "staging-eu-west" moves to the pinned section of the navigator
    And the pin is persisted to "storage.sqlite3"
    And the cluster is marked as pinned in the ContextNavigationState

  @failure @lifecycle
  Scenario: Merely visiting a cluster many times does not auto-pin it
    Given the operator has visited "dev-local" 20 times across multiple sessions
    When the ContextNavigationState evaluates the recents and pin lists
    Then "dev-local" does NOT appear in the pinned section (no auto-pin behavior)
    And "dev-local" appears only in the recents list based on visit frequency
    And the pin can only be set by an explicit operator gesture

  @happy @lifecycle
  Scenario: Unpin via explicit button click removes cluster from pinned section
    Given "prod-us-east-1" is in the pinned section
    When the operator right-clicks "prod-us-east-1" and selects "Unpin"
    Then a unpinAction gesture is recorded
    And "prod-us-east-1" is removed from the pinned section
    And moves to the recents list at the most recent position
    And the change is persisted to "storage.sqlite3"

  @failure @lifecycle
  Scenario: Pin action is not triggered by keyboard shortcut alone — explicit confirmation needed
    Given the operator presses a keyboard shortcut while "staging-eu-west" is focused
    When the shortcut is intended to pin the cluster
    Then the pin action requires the cluster to be the explicitly focused item in the navigator
    And the pin only applies to the focused cluster (not any last-visited or hovered cluster)
    And no accidental pins occur due to focus racing with hover state
