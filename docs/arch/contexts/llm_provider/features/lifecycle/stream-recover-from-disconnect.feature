# DDD role: BehaviouralSpecification
# Bounded context: llm_provider
# References: ADR-0008, ADR-0011

Feature: SSE stream disconnect — operator informed without silent reconnect
  As an operator
  I want to be explicitly told when the streaming response from the LLM provider was interrupted
  So that I can decide whether to retry rather than receive a silently incomplete response

  Background:
    Given an assistant chat session is open and the assistant is streaming a response
    And the SSE connection to the Anthropic API is in use

  @failure @lifecycle
  Scenario: SSE stream breaks mid-response — operator informed, no auto-reconnect
    Given the assistant has delivered 200 tokens of a streaming response
    When the TCP connection to the Anthropic API resets unexpectedly
    Then the LLMProviderAdapter detects the SSE stream disconnection
    And the adapter does NOT silently reconnect and resume from where the stream broke
    And the partial response already displayed in the UI remains visible (partial is better than none)
    And a toast message appears: "Response interrupted — network connection was lost"
    And the chat input is re-enabled immediately

  @failure @lifecycle
  Scenario: Connection reset before first token — operator sees a clear error, not an empty response
    Given the SSE connection was established but no tokens have been delivered
    When the TCP connection resets before any content arrives
    Then the adapter surfaces a "stream disconnected before first token" error
    And the chat UI shows "Failed to receive a response — check your network and try again"
    And no partial assistant message is shown (nothing to show)

  @happy @lifecycle
  Scenario: Operator manually retries after a stream disconnect — fresh request succeeds
    Given the previous stream was disconnected and the operator is shown the retry message
    When the operator resends the same message
    Then a fresh HTTP request is made to the Anthropic API (no resumed SSE stream)
    And the assistant begins streaming the response from the beginning
    And the response is delivered completely

  @security @lifecycle
  Scenario: No credential material is exposed in the stream error event
    Given the SSE stream disconnect error includes a transport-layer error message
    When the error is logged and displayed to the operator
    Then the error message does not contain any API key fragment, bearer token, or header value
    And the log entry redacts any HTTP header content that could expose credentials
