# DDD role: ChaosScenario
# Bounded context: assistant_chat
# Failure mode: F13 (LLM provider returns 503 / service unavailable)
# References: ADR-0041, ADR-0031, ADR-0035

Feature: LLM provider 503 pauses conversation and requires operator action to retry
  As a cluster operator
  I need the assistant to clearly signal provider unavailability
  So that I know the AI is unavailable and my conversation context is preserved for later retry

  Background:
    Given the assistant chat is open with a 3-turn conversation history
    And the configured LLM provider endpoint returns HTTP 503

  @chaos @network
  Scenario: Provider 503 on new message causes conversation to pause with clear error
    When the operator sends the message "Why is my Deployment pending?"
    Then the adapter receives HTTP 503 from the provider
    And the conversation is paused (no streaming begins)
    And the UI displays an inline message "AI provider unavailable — retry when ready"
    And the operator's message remains in the input area for easy retry
    And the conversation history (3 prior turns) is fully preserved

  @chaos @network
  Scenario: Operator retries manually after provider recovers and conversation resumes
    Given the conversation is paused due to a 503 error
    And the LLM provider has since recovered (returns 200)
    When the operator clicks "Retry"
    Then the adapter re-sends the last message to the provider
    And streaming begins normally
    And the assistant's response is appended to the conversation history
    And no duplicate messages are added to the history

  @chaos @network
  Scenario: Conversation context is not lost across provider-down and recovery cycle
    Given the conversation paused at turn 4 due to 503
    When the provider recovers and the operator retries
    Then the full conversation history (turns 1–3 plus the retried turn 4) is sent as context
    And the assistant response reflects awareness of all prior turns
