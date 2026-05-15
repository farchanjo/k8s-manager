# DDD role: Feature
# Bounded context: context_navigation
Feature: Pin a Kubernetes context to the sidebar

  As an operator
  I want to pin frequently-used contexts to the sidebar
  So that they remain reachable in one click regardless of how recently I used them

  Background:
    Given a kubeconfig has been loaded successfully
    And the kubeconfig declares a context "stable-prod"

  Scenario: Pinning a context places it in the pinned section
    Given "stable-prod" is not pinned
    When the operator pins "stable-prod"
    Then "stable-prod" appears in the pinned section of the sidebar
    And the pinned section sort order places "stable-prod" at the bottom of the existing pins

  Scenario: Pinned contexts are not pruned from the recents window
    Given the recents window already holds 32 entries
    And "stable-prod" is pinned and is the tail entry of the recents window
    When the operator selects 8 different contexts in sequence
    Then "stable-prod" remains in the recents window
    And no other recently-used context has been removed prematurely on its behalf

  Scenario: Reordering pinned contexts is persisted
    Given the operator has three pinned contexts in order [A, B, C]
    When the operator drags C to the first position
    Then the pinned section order becomes [C, A, B]
    And the order survives an application restart

  Scenario: Unpinning a context returns it to the recents-only behaviour
    Given "stable-prod" is pinned
    When the operator unpins "stable-prod"
    Then "stable-prod" no longer appears in the pinned section
    And "stable-prod" remains visible in the recents window if its last-used timestamp is recent enough
