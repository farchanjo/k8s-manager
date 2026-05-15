# DDD role: BehaviouralSpecification
# Bounded context: llm_provider
# References: ADR-0008

Feature: Provider 429 rate limit — Retry-After respected and operator informed
  As an operator
  I want K8sManager to respect the Retry-After header when the LLM provider returns 429
  So that my account is not further throttled by retrying too quickly

  Background:
    Given an assistant chat session is open
    And the LLM provider profile is configured for "anthropic-main"

  @failure @lifecycle
  Scenario: 429 response with Retry-After header — adapter waits the specified duration
    Given the operator sends a message to the assistant
    When the Anthropic API returns HTTP 429 with header "Retry-After: 5"
    Then the LLMProviderAdapter reads the Retry-After value (5 seconds)
    And the adapter waits 5 seconds before retrying the request (using Task.sleep)
    And the operator sees "Throttled — retrying in 5s" in the chat UI
    And no duplicate requests are sent during the wait period
    After 5 seconds the request is retried once
    And if the retry succeeds, the response is delivered normally

  @failure @lifecycle
  Scenario: 429 response without Retry-After — adapter uses default back-off of 30 seconds
    Given the Anthropic API returns HTTP 429 with no Retry-After header
    When the adapter does not find a Retry-After header
    Then the adapter waits the default 30-second backoff before retrying
    And the operator sees "Throttled — retrying in 30s"

  @failure @lifecycle
  Scenario: Retry after rate limit also receives 429 — operator is informed to wait
    Given the first retry after the 5-second wait also returns 429
    When the second 429 is received
    Then the adapter does NOT retry a third time automatically
    And the operator sees "Still throttled — please try again in a few minutes"
    And the chat input is re-enabled for the operator to retry manually

  @happy @lifecycle
  Scenario: Successful response after rate-limit retry is displayed normally
    Given the 429 back-off elapsed and the retry request succeeds
    When the response arrives from the Anthropic API
    Then the "Throttled" indicator is hidden
    And the assistant response is displayed in the chat UI normally
    And the conversation continues as if no rate limit occurred
