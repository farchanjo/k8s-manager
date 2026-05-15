# DDD role: BehaviouralSpecification
# Bounded context: llm_provider
# References: ADR-0008

Feature: Localhost provider URL allowed when localOnly=true flag is set
  As an operator running Ollama locally
  I want to point K8sManager at http://localhost:11434 for local inference
  So that I can use an offline-capable LLM without a cloud API key

  Background:
    Given the operator is configuring a new LLM provider profile in Settings

  @happy @lifecycle
  Scenario: Provider URL with localhost and localOnly=true is accepted by policy
    When the operator sets providerURL to "http://localhost:11434" and enables "Local provider" toggle (localOnly=true)
    Then the ProviderProfile Rego policy evaluates localOnly=true for the URL "http://localhost:11434"
    And the policy allows the configuration (localhost is permitted when localOnly is explicitly set)
    And the ProviderProfile is saved to "storage.sqlite3"
    And no API key is required (the key field may be empty for local providers)
    And the assistant can send requests to "http://localhost:11434/api/chat"

  @happy @lifecycle
  Scenario: LM Studio at localhost:1234 with localOnly=true is also allowed
    When the operator sets providerURL to "http://localhost:1234" and localOnly=true
    Then the policy allows the configuration
    And the provider profile is saved successfully

  @failure @lifecycle
  Scenario: Localhost URL without localOnly=true flag is denied by policy
    When the operator sets providerURL to "http://localhost:8080" without enabling the "Local provider" toggle
    Then the ProviderProfile Rego policy evaluates localOnly=false for a localhost URL
    And the policy denies the configuration with reason "localhost URLs require the localOnly flag to be set"
    And the Settings panel shows "Enable 'Local provider' to use a localhost endpoint"
    And the ProviderProfile is NOT saved

  @security @lifecycle
  Scenario: Non-localhost HTTP URL without TLS is denied regardless of localOnly flag
    When the operator sets providerURL to "http://192.168.1.100:8080" (a LAN IP, not localhost)
    And sets localOnly=true
    Then the policy denies the configuration because a non-localhost HTTP URL without TLS is not permitted
    And the error message suggests using HTTPS: "Use HTTPS for non-localhost provider endpoints"
