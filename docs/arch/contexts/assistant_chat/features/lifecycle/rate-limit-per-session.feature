# DDD role: BehaviouralSpecification
# Bounded context: assistant_chat
# References: ADR-0009, ADR-0010

Feature: Per-session tool invocation rate limiting
  As an operator
  I want tool invocations to be rate-limited per chat session
  So that runaway assistant behavior or misconfigured loops do not exhaust cluster API budget

  Background:
    Given an assistant chat session "chat-session-1" is open
    And the per-session tool invocation limit is 20 per minute

  @failure @lifecycle
  Scenario: Tool invocation limit reached — next invocation is deferred
    Given 20 tool invocations have been dispatched in the last 60 seconds
    When the assistant generates a tool_use for "kube_list_pods"
    Then the MCP host checks the session's invocation counter
    And the counter has reached the limit of 20 per minute
    And the invocation is queued (deferred) rather than dispatched immediately
    And the operator sees a status indicator "Tool calls throttled — waiting for rate limit to reset"
    And after the 60-second window resets, the deferred invocation is dispatched

  @failure @lifecycle
  Scenario: Hard reject instead of defer when queue is full
    Given 20 tool invocations have been dispatched and 5 more are already queued
    When the assistant generates another tool_use
    Then the MCP host rejects the invocation immediately with "rate limit exceeded — too many queued calls"
    And a tool_result error is returned to the assistant
    And the conversation continues with the assistant acknowledging the throttle

  @happy @lifecycle
  Scenario: Rate limit counter resets after 60 seconds
    Given 20 tool invocations were dispatched starting at T=0
    When T=61 seconds elapses
    Then the invocation counter resets to 0
    And the next tool_use is dispatched without throttling

  @happy @lifecycle
  Scenario: Different chat sessions have independent rate limit counters
    Given "chat-session-1" has dispatched 20 tool invocations in the last 60 seconds (at limit)
    And "chat-session-2" has dispatched 0 tool invocations
    When the assistant in "chat-session-2" generates a tool_use
    Then "chat-session-2"'s invocation is dispatched immediately (its counter is independent)
    And "chat-session-1" remains throttled until its window resets
