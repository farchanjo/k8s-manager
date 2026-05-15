# DDD role: ChaosScenario
# Bounded context: assistant_chat
# Failure mode: F12 (MCP tool hangs beyond timeout threshold)
# References: ADR-0041, ADR-0031, ADR-0034

Feature: Hanging MCP tool call is cancelled after 30 seconds with inline error
  As a cluster operator
  I need hung tool calls to be cancelled automatically
  So that the assistant conversation is not frozen indefinitely waiting for a non-responsive tool

  Background:
    Given the assistant chat is open
    And an MCP tool "kube_logs" is registered and normally returns within 2 seconds
    And the tool is configured to hang indefinitely (simulated by blocking the InMemoryTransport)

  @chaos @network
  Scenario: Tool hang beyond 30 seconds triggers automatic cancellation
    When the assistant invokes the "kube_logs" tool
    Then the adapter starts a 30-second deadline timer for the tool call
    And after 30 seconds without a response the adapter cancels the tool call
    And the cancellation is surfaced inline in the conversation as "Tool timeout: kube_logs exceeded 30s"
    And the conversation remains in a valid, continuable state

  @chaos @network
  Scenario: Timed-out tool call does not block subsequent tool calls in the same turn
    Given the "kube_logs" tool timed out
    When the assistant invokes a different tool "get_pod" in the same turn
    Then "get_pod" is dispatched without waiting for the cancelled "kube_logs" call
    And "get_pod" returns its result normally
    And both the timeout error and the "get_pod" result appear inline in the conversation

  @chaos @network
  Scenario: The InMemoryTransport does not leak file descriptors or goroutines after a timeout
    Given a "kube_logs" tool call timed out and was cancelled
    When the tool hang is released after cancellation (simulated by unblocking the transport)
    Then no response from "kube_logs" is delivered to the conversation
    And the transport's internal state is fully cleaned up (no dangling channels or FDs)
    And the metric "mcp_tool_timeout_total" increments by 1

  @chaos @network
  Scenario: Tool timeout threshold is configurable and honoured at the configured value
    Given the tool timeout is set to 10 seconds via application settings
    When the "kube_logs" tool hangs
    Then the adapter cancels the call after 10 seconds (not 30)
    And the inline error reads "Tool timeout: kube_logs exceeded 10s"
