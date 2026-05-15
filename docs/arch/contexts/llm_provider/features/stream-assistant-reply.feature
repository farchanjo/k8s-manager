# DDD role: Feature
# Bounded context: llm_provider
Feature: Stream an assistant reply through the provider port

  As the assistant_chat context
  I want to receive a normalised stream of events from any provider
  So that I can render tokens, tool calls, and usage without caring
  which provider produced them

  Background:
    Given a provider profile "primary" is configured
    And the operator has issued an assistant turn with a user message

  Scenario: Anthropic provider delivers normalised events
    Given "primary" is an Anthropic profile with model "claude-sonnet-4-6"
    When the provider port runs the turn
    Then the first event is a "delta" with text from the model
    And at most one "usage" event is emitted before "finish"
    And the stream terminates with a "finish" event whose reason is "stop"

  Scenario: OpenAI provider delivers normalised events
    Given "primary" is an OpenAI profile with model "gpt-5.3"
    When the provider port runs the turn
    Then the first event is a "delta" with text from the model
    And the stream terminates with a "finish" event whose reason is "stop"

  Scenario: Tool use is surfaced as start, deltas, and finish events
    Given the assistant turn declares one tool named "kube_list_pods"
    And the chosen provider supports tool use
    When the provider port runs the turn and the model decides to call the tool
    Then a "tool_use_start" event is emitted with the tool's name
    And one or more "tool_use_delta" events deliver the JSON arguments in order
    And a "tool_use_finish" event delivers the complete UTF-8 JSON arguments string
    And the stream pauses awaiting tool_result before any further "delta" arrives

  Scenario: An OpenAI-compatible server without usage events degrades gracefully
    Given "primary" is an OpenAI-compatible profile with a server that omits usage events
    When the provider port runs the turn
    Then no "usage" event is emitted
    And the stream still terminates with a "finish" event whose reason is "stop"
    And the absent-usage condition is recorded in the diagnostics counter

  Scenario: Cancellation aborts the in-flight HTTP request quickly
    Given an assistant turn is mid-stream
    When the assistant_chat context cancels the turn task
    Then the provider adapter aborts the HTTP request within 200 milliseconds
    And the stream terminates with a "finish" event whose reason is "cancelled"
    And no further events are emitted after the "finish"

  Scenario: A provider 429 surfaces a typed error
    Given the provider returns a 429 Too Many Requests with a Retry-After header
    When the provider port runs the turn
    Then the stream terminates with a "finish" event whose reason is "error"
    And the detail field includes the suggested retry interval
    And the detail field does not include any credential material
