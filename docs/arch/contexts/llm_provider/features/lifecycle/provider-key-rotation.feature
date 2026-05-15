# DDD role: BehaviouralSpecification
# Bounded context: llm_provider
# References: ADR-0008, ADR-0010, ADR-0018
# CUE schema: contexts/llm_provider/schemas/provider_profile.cue

Feature: LLM provider API key rotation via Keychain
  As an operator
  I want to replace my Anthropic API key in Settings and have the change take effect immediately
  So that I can rotate credentials without restarting K8sManager

  Background:
    Given a ProviderProfile for "anthropic-main" is configured with an existing API key in Keychain
    And the Keychain service is "com.archanjo.K8sManager.llm" with account "anthropic-main"

  @happy @lifecycle
  Scenario: Operator rotates Anthropic key in Settings — Keychain entry overwritten, next request uses new key
    When the operator enters a new API key in Settings → LLM Provider → Anthropic
    And presses "Save"
    Then the LLMKeyStorePort overwrites the Keychain entry for account "anthropic-main" using kSecClassGenericPassword
    And the Keychain entry is updated to the new key value
    And the new key is accessible with accessibility class "kSecAttrAccessibleWhenUnlockedThisDeviceOnly"
    When the assistant sends the next message to the Anthropic API
    Then the Authorization header carries the new key (not the old one)
    And no app restart is required

  @security @lifecycle
  Scenario: Old API key is not retained in memory after rotation
    Given the old key "sk-old-key" was used for the last request
    When the new key "sk-new-key" is saved to Keychain
    Then the LLMKeyStorePort in-memory cache is invalidated
    And the next retrieval of the key from the LLMKeyStorePort returns "sk-new-key"
    And "sk-old-key" is not accessible through any application code path after the invalidation

  @security @lifecycle
  Scenario: API key is never written to any log file or SQLite row
    Given the operator saves a new API key
    When the key is written to Keychain
    Then no log line under "~/.config/k8smanager/logs/" contains any part of the key value
    And no row in "storage.sqlite3" contains the key value
    And the ProviderProfile row in SQLite stores only the "keyAlias" (Keychain account name), not the key itself

  @failure @lifecycle
  Scenario: Keychain write failure surfaces a user-friendly error
    Given the macOS Keychain is locked and unavailable
    When the operator attempts to save a new API key
    Then the LLMKeyStorePort returns a KeychainError
    And the Settings panel shows "Failed to save API key — please unlock the Keychain and try again"
    And the old key remains in Keychain (no partial update)
