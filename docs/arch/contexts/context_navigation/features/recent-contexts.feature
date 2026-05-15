# DDD role: Feature
# Bounded context: context_navigation
Feature: Maintain a recents window of Kubernetes contexts

  As an operator
  I want K8sManager to remember which contexts I have used recently
  So that I can hop back without scrolling the full kubeconfig

  Background:
    Given a kubeconfig has been loaded successfully

  Scenario: First-time launch shows no recents
    Given the application has never run on this workstation before
    When the operator opens the sidebar
    Then the recents section is empty
    And the operator is invited to pick a context from the full list

  Scenario: Each selection updates the recents window
    Given the recents window is initially empty
    When the operator selects "dev"
    And the operator selects "staging"
    And the operator selects "dev"
    Then the recents window order is ["dev", "staging"]
    And the useCount for "dev" is 2 and for "staging" is 1

  Scenario: Recents survive an application restart
    Given the recents window contains ["dev", "staging"]
    When the application is quit and relaunched
    Then the recents window still contains ["dev", "staging"] in the same order

  Scenario: A context that disappears from kubeconfig is pruned from recents
    Given the recents window contains ["dev", "staging", "old-prod"]
    When the kubeconfig is reloaded and "old-prod" is no longer present
    Then the recents window becomes ["dev", "staging"]
    And no domain event is emitted for the prune (it is housekeeping, not a selection)
