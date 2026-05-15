# DDD role: ChaosScenario
# Bounded context: cluster_intelligence
# Failure mode: oversized tool result exceeds context budget (F12 variant)
# References: ADR-0041, ADR-0031, ADR-0034

Feature: kube_logs returning 1 MB is truncated to 256 KiB with a truncation marker
  As a cluster operator
  I need large tool results to be truncated before being injected into the LLM context
  So that oversized log payloads do not exhaust the context window or cause silent failures

  Background:
    Given the assistant has invoked the "kube_logs" MCP tool for a high-verbosity pod
    And the Kubernetes API returns 1 MB of log lines for the requested pod/container

  @chaos @network
  Scenario: 1 MB log result is truncated to 256 KiB and a marker is appended
    When the kube_logs tool call completes with a 1 048 576-byte payload
    Then the MCP adapter truncates the result to 262 144 bytes (256 KiB)
    And a truncation marker is appended: "[TRUNCATED — output exceeded 256 KiB; showing last 256 KiB]"
    And the truncated result plus marker is what the assistant receives as the tool result

  @chaos @network
  Scenario: The assistant can reference the truncation marker in its response
    Given the truncated log result with marker has been delivered to the assistant
    When the assistant processes the tool result
    Then the assistant's response acknowledges that the log was truncated
    And the assistant offers guidance based on the available 256 KiB portion
    And the assistant does not hallucinate content beyond the truncated boundary

  @chaos @network
  Scenario: Tool results within the 256 KiB limit are not truncated
    Given the kube_logs tool returns a 100 KiB payload
    When the MCP adapter receives the result
    Then the result is delivered to the assistant without modification
    And no truncation marker is appended
    And the metric "mcp_result_truncated_total" does not increment

  @chaos @network
  Scenario: Truncation boundary is byte-accurate and does not split a UTF-8 character
    Given the 256 KiB truncation point falls in the middle of a multi-byte UTF-8 sequence
    When the MCP adapter truncates the result
    Then the truncation is adjusted backward to the nearest valid UTF-8 character boundary
    And the delivered result is valid UTF-8 without replacement characters
