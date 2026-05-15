# DDD role: BehaviouralSpecification
# Bounded context: assistant_chat
# References: ADR-0008, ADR-0011

Feature: Assistant streaming response cancellation within 200 ms
  As an operator
  I want to cancel a streaming assistant response mid-flight
  So that I can stop a slow or irrelevant response without waiting for it to complete

  Background:
    Given an assistant chat session is open
    And the LLM provider is streaming a response from the Anthropic Messages API

  @happy @lifecycle
  Scenario: Cancel button cancels the upstream SSE stream within 200 milliseconds
    Given the assistant is streaming a long response (more than 500 tokens)
    When the operator presses the Cancel button in the chat UI
    Then the AssistantChatActor sends Task.cancel to the streaming task
    And the upstream HTTP request to the Anthropic API is aborted within 200 milliseconds
    And the SSE stream is closed from the client side
    And the partial response already displayed in the UI remains visible
    And the chat input is re-enabled immediately

  @failure @lifecycle
  Scenario: Cancel during tool call execution also cancels the pending tool call
    Given the assistant has issued a tool_use block and the MCP tool is executing
    When the operator presses Cancel
    Then Task.cancel propagates to the MCP tool execution task
    And the kube API call underlying the tool is cancelled (if in-flight)
    And the conversation state is rolled back to before the tool_use was issued
    And a "(cancelled)" indicator is shown in the message history

  @failure @lifecycle
  Scenario: SSE stream disconnects unexpectedly — operator is informed without auto-retry
    Given the streaming response is in progress
    When the SSE stream connection resets unexpectedly (TCP RST or network interruption)
    Then the LLMProviderAdapter detects the stream disconnection
    And the adapter does NOT silently reconnect and resume the response
    And the operator is shown "Response interrupted — network connection was lost"
    And the chat input is re-enabled for the operator to re-send the message if desired

  @lifecycle @happy
  Scenario: Normal completion of a streaming response ends gracefully
    Given the assistant is streaming a response
    When the LLM provider sends the final SSE event (message_stop or [DONE])
    Then the stream is closed gracefully
    And the complete response is displayed in the chat UI
    And the chat session is persisted to the "chat_messages" table in "storage.sqlite3"
    And the chat input is re-enabled
