# DDD role: BehaviouralSpecification
# Bounded context: llm_provider
# References: ADR-0008

Feature: Localhost provider URL denied when localOnly flag is absent
  As a security-conscious operator
  I want localhost URLs to be blocked by default so that a misconfigured URL does not silently route to a local service
  So that only explicit opt-in allows local HTTP endpoints

  Background:
    Given the operator is configuring a new LLM provider profile in Settings
    And the "Local provider" toggle is OFF (localOnly=false by default)

  @security @lifecycle
  Scenario: http://localhost:8080 without localOnly flag is rejected by the provider policy
    When the operator sets providerURL to "http://localhost:8080" and does not enable the localOnly toggle
    Then the ProviderProfile Rego policy evaluates the URL against the allowed-endpoint rules
    And the policy finds localOnly=false for a localhost HTTP URL
    And the policy returns a deny decision
    And the Settings panel shows "Enable 'Local provider' to use a localhost endpoint"
    And the ProviderProfile is NOT saved to "storage.sqlite3"

  @security @lifecycle
  Scenario: http://127.0.0.1:8080 without localOnly flag is also denied
    When the operator sets providerURL to "http://127.0.0.1:8080" without the localOnly toggle
    Then the policy also rejects this URL (127.0.0.1 is treated the same as localhost)
    And the denial reason is "localhost URLs require the localOnly flag"

  @security @lifecycle
  Scenario: https://localhost:443 without localOnly flag is denied
    When the operator sets providerURL to "https://localhost:443" without the localOnly toggle
    Then the policy denies HTTPS localhost URLs as well (even with TLS, localhost requires the flag)
    And the denial message guides the operator to enable "Local provider"

  @happy @lifecycle
  Scenario: Public HTTPS provider URL without localOnly flag is allowed
    When the operator sets providerURL to "https://api.anthropic.com" with no localOnly toggle
    Then the policy allows the configuration (public HTTPS with no localhost component)
    And the ProviderProfile is saved successfully with an API key required
