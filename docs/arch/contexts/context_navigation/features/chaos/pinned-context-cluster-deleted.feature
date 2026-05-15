# DDD role: ChaosScenario
# Bounded context: context_navigation
# References: ADR-0005, ADR-0023, ADR-0026
# CUE schema: contexts/context_navigation/schemas/recent_context.cue

Feature: Pinned context cluster deleted from kubeconfig mid-session
  As an operator
  I want stale pinned contexts to be clearly flagged when their cluster
  disappears from kubeconfig so that I can repin or clean up intentionally
  So that a deleted cluster entry does not silently remain in the navigator

  Background:
    Given the operator has pinned "prod-eu-west-1" and "staging-eu-west" in the context navigator
    And "prod-eu-west-1" has a ClusterSessionActor in "connected" state
    And the kubeconfig file is being watched for changes (inotify / kqueue EVFILT_VNODE)

  @chaos @failure
  Scenario: Pinned context cluster entry removed from kubeconfig — pin marked stale
    When the operator removes the "prod-eu-west-1" context from the kubeconfig file
    And K8sManager detects the kubeconfig change via EVFILT_VNODE and reloads it
    Then the ContextNavigationState finds that "prod-eu-west-1" no longer exists in the kubeconfig
    And the pin record for "prod-eu-west-1" is marked with status "stale"
    And the navigator renders "prod-eu-west-1" with a "Cluster not found" badge and muted styling
    And the ClusterSessionActor for "prod-eu-west-1" is gracefully torn down
    And the pinned entry for "staging-eu-west" is unaffected

  @chaos @failure
  Scenario: Operator prompted to repin or remove a stale pinned context
    Given the pin for "prod-eu-west-1" is in "stale" state after its cluster was deleted
    When the operator opens the context navigator
    Then a contextual action menu on the stale pin shows two options: "Remove pin" and "Repin when restored"
    When the operator selects "Remove pin"
    Then the pin record for "prod-eu-west-1" is deleted from "storage.sqlite3"
    And the stale entry is removed from the navigator immediately
    And no domain event is emitted for the removal (housekeeping, not a selection action)

  @chaos @recovery
  Scenario: Stale pin resolved automatically when cluster is re-added to kubeconfig
    Given the pin for "prod-eu-west-1" is in "stale" state
    When the operator adds "prod-eu-west-1" back to the kubeconfig file
    And K8sManager detects the kubeconfig change and reloads it
    Then the ContextNavigationState finds "prod-eu-west-1" in the updated kubeconfig
    And the pin record status transitions from "stale" to "active"
    And the "Cluster not found" badge is cleared from the navigator entry
    And the ClusterSessionActor for "prod-eu-west-1" re-establishes its session automatically
