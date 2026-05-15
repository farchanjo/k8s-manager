# DDD role: Feature
# Bounded context: assistant_chat
Feature: Streaming an assistant turn end to end

  As an operator
  I want the assistant to stream its reply as it is produced
  So that the UI feels live and I can read while the model continues
  generating

  Background:
    Given a chat session is open against the active provider profile
    And the in-process MCP server is running with the read-only tool registry

  Scenario: A pure-text turn renders tokens as they arrive
    Given the operator sends "what is happening on my cluster?"
    When the provider streams the assistant reply
    Then the chat surface shows the text growing token by token
    And the UI remains responsive throughout (60 fps held)
    And the final message has streaming=false and finishReason="stop"

  Scenario: A tool-use turn invokes the MCP server and resumes the stream
    Given the operator sends "list the pods in namespace default"
    When the model emits a tool_use_start for "kube_list_pods"
    Then the chat surface shows a pending tool-call indicator
    And the in-process MCP server executes the tool against the pinned context
    And the ToolCallRecord is persisted with status="running" then "succeeded"
    And the provider stream is resumed with the tool_result
    And the assistant's textual summary streams in afterwards

  Scenario: Cancelling a turn cancels the provider and any tool in flight
    Given a turn is mid-stream
    When the operator presses the cancel button
    Then the provider HTTP request aborts within 200 milliseconds
    And any tool currently executing receives a cancellation
    And the final message has streaming=false and finishReason="cancelled"
    And the ToolCallRecord for the in-flight tool has status="cancelled"

  Scenario: A denied tool call surfaces a clear message
    Given the operator sends a prompt that causes the model to attempt "kube_delete_pod"
    When the host receives the tool_use event
    Then the host rejects the call with reason "tool not registered"
    And a ToolCallRecord is persisted with status="denied_by_policy"
    And the assistant is informed via tool_result that the call was denied
    And the cluster is unchanged

  Scenario: Network failure mid-stream is recorded as an error
    Given a turn is mid-stream
    When the provider returns an unrecoverable network error
    Then the message has streaming=false and finishReason="error"
    And the detail mentions the failure mode in operator-friendly terms
    And no credential material appears in the detail string

  Scenario: Re-opening the session re-renders the persisted log
    Given the session contains three turns including one tool call
    When the operator closes the session and re-opens it later
    Then every message renders with its content, timestamp, and finish reason
    And the tool-call card renders with the persisted arguments and result
