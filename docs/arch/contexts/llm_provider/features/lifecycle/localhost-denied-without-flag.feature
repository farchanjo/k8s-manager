# DDD role: BehaviouralSpecification
# Bounded context: llm_provider
# References: ADR-0008
#
# NOTE 2026-05-15: all scenarios from this file have been consolidated into
# localhost-allowed-for-ollama.feature as a Scenario Outline with an Examples
# table parameterising host, port, localOnly, and expected policy decision.
# This file is retained to preserve any external cross-references.
# The normative scenarios live at:
#   docs/arch/contexts/llm_provider/features/lifecycle/localhost-allowed-for-ollama.feature

Feature: Localhost provider URL denied when localOnly flag is absent
  As a security-conscious operator
  I want localhost URLs to be blocked by default so that a misconfigured URL does not silently route to a local service
  So that only explicit opt-in allows local HTTP endpoints

  Background:
    Given the operator is configuring a new LLM provider profile in Settings
    And the "Local provider" toggle is OFF (localOnly=false by default)

  @security @lifecycle
  Scenario: http://localhost:8080 without localOnly flag is rejected — see Outline in localhost-allowed-for-ollama.feature
    When the operator sets providerURL to "http://localhost:8080" and does not enable the localOnly toggle
    Then the ProviderProfile Rego policy evaluates the URL against the allowed-endpoint rules
    And the policy finds localOnly=false for a localhost HTTP URL
    And the policy returns a deny decision
    And the Settings panel shows "Enable 'Local provider' to use a localhost endpoint"
    And the ProviderProfile is NOT saved to "storage.sqlite3"
