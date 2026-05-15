# DDD role: Feature
# Bounded context: llm_provider
Feature: Configure an LLM provider profile

  As an operator
  I want to add and edit LLM provider profiles
  So that the assistant can talk to the model I want, with the sampling
  knobs I want, against the endpoint I trust

  Background:
    Given the application has been launched on a fresh installation
    And the operator has opened the LLM providers panel in settings

  Scenario: Adding an Anthropic profile stores the API key in Keychain
    Given the operator selects the "Anthropic" kind
    And enters an API key beginning with "sk-ant-"
    And selects the model "claude-sonnet-4-6"
    And accepts the default temperature 0.7 and max output tokens 4096
    When the operator saves the profile
    Then a new ProviderProfile exists with kind "anthropic"
    And the API key is stored in the macOS Keychain under service "com.archanjo.K8sManager.llm"
    And the SQLite "provider_profiles" row contains no copy of the API key

  Scenario: Adding an OpenAI-compatible profile requires a baseURL
    Given the operator selects the "OpenAI-compatible" kind
    And does not enter a baseURL
    When the operator attempts to save the profile
    Then the save is rejected with a validation message that mentions the baseURL field
    And no Keychain entry is created
    And no SQLite row is inserted

  Scenario: Adding an Ollama profile against a local instance works offline
    Given a local Ollama instance is reachable at "http://127.0.0.1:11434"
    And the operator selects the "OpenAI-compatible" kind
    And enters baseURL "http://127.0.0.1:11434/v1"
    And enters an empty API key (Ollama accepts any string)
    And selects the model "qwen3:32b-instruct"
    When the operator saves the profile
    Then a new ProviderProfile is created with kind "openai_compatible"
    And the feature-detection step records that streaming is supported and usage events are absent

  Scenario: Editing a profile updates only the requested fields
    Given a profile "primary" with temperature 0.7 exists
    When the operator changes temperature to 0.2 and saves
    Then the profile's samplingDefaults.temperature is 0.2
    And the API key is unchanged in Keychain
    And other fields (modelId, baseURL, maxOutputTokens) are unchanged

  Scenario: Deleting a profile removes its Keychain entry
    Given a profile "old" exists with a Keychain entry under "com.archanjo.K8sManager.llm"
    When the operator deletes the profile
    Then the SQLite row is removed
    And the matching Keychain entry is deleted
    And any chat session that referenced the profile is offered a re-selection prompt
