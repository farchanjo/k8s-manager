# DDD role: ChaosScenario
# Bounded context: llm_provider
# Failure mode: F14 (API key revoked mid-stream by provider)
# References: ADR-0041, ADR-0035

Feature: Anthropic 401 mid-stream aborts response and prompts operator to update key
  As a cluster operator
  I need the assistant to abort cleanly when the API key is revoked during streaming
  So that I know to update my credentials without the conversation entering a broken state

  Background:
    Given the assistant has begun streaming a response using an Anthropic API key
    And the key is revoked by the Anthropic platform while the stream is in-flight

  @chaos @cred
  Scenario: 401 received mid-stream causes adapter to abort and surface key-update prompt
    When the Anthropic SSE stream delivers a 401 Unauthorized event mid-response
    Then the adapter aborts the stream immediately
    And any partial streamed content already displayed is marked with a warning banner "[Response interrupted]"
    And the UI surfaces "API key revoked — update your key in Settings to continue"
    And the conversation is not left in a state that accepts new messages until the key is updated

  @chaos @cred
  Scenario: Operator updates the API key in Settings and the conversation resumes
    Given the UI is showing "API key revoked"
    When the operator navigates to Settings and enters a valid replacement API key
    And the operator clicks "Save"
    Then the new key is stored in the Keychain
    And the assistant is ready to accept new messages
    And the operator can re-send the last message that triggered the interrupted stream
    And the re-sent message streams successfully using the new key

  @chaos @cred
  Scenario: Partial streamed content is preserved in the conversation history after key revocation
    Given the stream was interrupted after delivering 200 tokens of a partial response
    When the operator views the conversation history
    Then the 200-token partial response is visible in the history
    And it is labeled "[Incomplete — stream interrupted]"
    And the conversation turn count does not increment for the incomplete response
