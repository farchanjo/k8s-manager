# DDD role: Feature
# Bounded context: context_navigation
Feature: Switch the active Kubernetes context

  As an operator
  I want to switch between Kubernetes contexts inside K8sManager
  So that I can inspect different clusters without editing kubeconfig manually

  Background:
    Given a kubeconfig has been loaded successfully
    And the kubeconfig declares contexts "dev", "staging", and "prod"

  Scenario: Selecting a context becomes the active context
    Given the active context is "dev"
    When the operator selects "staging" from the sidebar
    Then the active context is "staging"
    And the selectedBy field is "user"
    And the recents window has "staging" as its first entry

  Scenario: Selecting the current context is a no-op
    Given the active context is "dev"
    When the operator selects "dev" from the sidebar
    Then the active context is still "dev"
    And the recents window order is unchanged

  Scenario: Selection emits a domain event
    Given the active context is "dev"
    When the operator selects "prod" from the sidebar
    Then a domain event "ActiveContextChanged" is emitted with previousContextId="<id-of-dev>" and currentContextId="<id-of-prod>"
    And other contexts subscribed to the event receive it before the UI animation completes

  Scenario: Reload of kubeconfig that drops the active context falls back gracefully
    Given the active context is "prod"
    When the kubeconfig is reloaded
    And "prod" is no longer declared under contexts[]
    Then the active context becomes the kubeconfig-level current-context if it still resolves
    And the selectedBy field is "fallback"
    And the operator is shown a non-blocking banner explaining the fallback
