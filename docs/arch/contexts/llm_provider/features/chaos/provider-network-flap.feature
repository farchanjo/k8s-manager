# DDD role: ChaosScenario
# Bounded context: llm_provider
# Failure mode: TCP reset mid-stream (network flap without silent reconnect)
# References: ADR-0041, ADR-0035

Feature: TCP reset mid-stream surfaces error to operator without silent reconnect
  As a cluster operator
  I need the adapter to surface network interruptions during streaming
  So that I am never unaware that the response I see is incomplete

  Background:
    Given the assistant has begun streaming a response from the Anthropic API
    And a TCP reset (RST) is injected into the connection while the stream is delivering tokens

  @chaos @network
  Scenario: TCP RST during SSE stream causes adapter to abort without silent reconnect
    When the TCP RST is received by the adapter mid-stream
    Then the adapter does NOT silently reconnect and resume streaming
    And the partially delivered response is marked "[Response interrupted — connection reset]"
    And the UI surfaces the inline error "Connection to AI provider was reset"
    And the conversation is paused waiting for operator action

  @chaos @network
  Scenario: Operator retries explicitly and streaming resumes from the beginning of the turn
    Given the connection-reset error is displayed
    When the operator clicks "Retry"
    Then a new HTTP request is issued to the Anthropic API for the same conversation turn
    And streaming begins fresh from the start of the turn (not mid-stream continuation)
    And the incomplete partial response is replaced by the new complete response

  @chaos @network
  Scenario: Multiple TCP resets on retry are reported without infinite retry loop
    Given the network is repeatedly resetting connections
    When the operator retries and encounters two more TCP resets
    Then the adapter surfaces each reset as a distinct error
    And the adapter does NOT auto-retry more than 0 times per operator action
    And the UI counts the errors: "Connection reset 3 times — check your network"

  @chaos @network
  Scenario: A successful stream following a TCP reset is stored in full conversation history
    Given a TCP reset occurred on the first attempt
    When the operator retries and the stream completes successfully
    Then only the successful complete response is recorded in the conversation history
    And the incomplete partial response from the first attempt is discarded
