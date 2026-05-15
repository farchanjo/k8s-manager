# DDD role: BehaviouralSpecification
# Bounded context: llm_provider
# References: ADR-0008
#
# Refactored 2026-05-15: merged with localhost-denied-without-flag.feature into
# a single Scenario Outline parameterising host, port, localOnly, and expected
# policy decision.  Duplicated scenario pairs replaced by the Examples table.
# The original non-localhost HTTP and HTTPS public URL edge-cases are preserved
# as standalone scenarios below the Outline.

Feature: Provider URL localhost policy — allow with localOnly flag, deny without
  As an operator
  I want the ProviderProfile Rego policy to permit localhost URLs only when
  the localOnly flag is explicitly set and to deny them otherwise
  So that misconfigured URLs never silently route traffic to a local service

  Background:
    Given the operator is configuring a new LLM provider profile in Settings

  @security @lifecycle
  Scenario Outline: Localhost URL policy decision depends on localOnly flag
    When the operator sets providerURL to "http://<host>:<port>" and localOnly is <localOnly>
    Then the ProviderProfile Rego policy evaluates localOnly=<localOnly> for the URL "http://<host>:<port>"
    And the policy decision is <expected>
    And when <expected> is "allow" the ProviderProfile is saved to "storage.sqlite3"
    And when <expected> is "deny" the Settings panel shows "Enable 'Local provider' to use a localhost endpoint"
    And when <expected> is "deny" the ProviderProfile is NOT saved

    Examples:
      | host        | port  | localOnly | expected |
      | localhost   | 11434 | true      | allow    |
      | localhost   | 1234  | true      | allow    |
      | localhost   | 8080  | false     | deny     |
      | localhost   | 8080  | true      | allow    |
      | 127.0.0.1   | 8080  | false     | deny     |
      | 127.0.0.1   | 11434 | true      | allow    |

  @security @lifecycle
  Scenario: HTTPS localhost URL without localOnly flag is also denied
    When the operator sets providerURL to "https://localhost:443" without enabling the "Local provider" toggle
    Then the ProviderProfile Rego policy denies the configuration
    And the denial message guides the operator to enable "Local provider"

  @security @lifecycle
  Scenario: Non-localhost HTTP URL on a LAN IP is denied regardless of localOnly flag
    When the operator sets providerURL to "http://192.168.1.100:8080" (a LAN IP, not localhost)
    And sets localOnly=true
    Then the policy denies the configuration because a non-localhost HTTP URL without TLS is not permitted
    And the error message suggests using HTTPS: "Use HTTPS for non-localhost provider endpoints"

  @happy @lifecycle
  Scenario: Public HTTPS provider URL without localOnly flag is allowed
    When the operator sets providerURL to "https://api.anthropic.com" with no localOnly toggle
    Then the policy allows the configuration (public HTTPS with no localhost component)
    And the ProviderProfile is saved successfully with an API key required
