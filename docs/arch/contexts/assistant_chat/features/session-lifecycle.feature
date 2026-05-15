# DDD role: Feature
# Bounded context: assistant_chat
Feature: Chat session lifecycle

  As an operator
  I want to manage multiple chat sessions
  So that I can keep separate threads for different clusters or topics

  Background:
    Given the application is launched

  Scenario: Creating a session binds it to the current provider profile
    Given the active provider profile is "primary"
    When the operator creates a new chat session
    Then the new session has providerProfileId equal to "primary"'s id
    And the session's title defaults to "New chat" pending the first user message
    And the system prompt defaults to the operator's last-saved default

  Scenario: The session title auto-updates from the first user message
    Given a new session has been created
    When the operator sends "investigate slow rollouts on namespace prod"
    Then the session title becomes a short summary of that message
    And the title length does not exceed 120 characters

  Scenario: Pinning a session to a Kubernetes context biases tool calls
    Given the operator pins the session to context "prod-east"
    When the assistant calls "kube_list_pods" without specifying a context
    Then the MCP server scopes the call to "prod-east"

  Scenario: Archiving a session hides it from the sidebar
    Given the session is currently in status "active"
    When the operator archives the session
    Then the session status becomes "archived"
    And the session no longer appears in the main session list
    And the session remains visible in the "Archived" filter

  Scenario: Deleting a session is reversible until vacuum
    Given the session is currently in status "active"
    When the operator deletes the session
    Then the session status becomes "trash"
    And the session is hidden from the main session list
    And the operator can restore it from the "Trash" filter
    And the periodic vacuum task permanently removes trashed sessions after 7 days

  Scenario: Provider profile deletion offers re-selection for impacted sessions
    Given a session is bound to provider profile "primary"
    When the operator deletes "primary"
    Then on the next attempt to send a turn in the affected session, the chat
      surface prompts the operator to pick a new provider profile
    And the session's providerProfileId is updated on confirmation
