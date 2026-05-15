# DDD role: ChaosScenario
# Bounded context: cluster_connectivity
# Failure mode: F2 (credential expiry mid-request)
# References: ADR-0041, ADR-0025

Feature: Token expiry detected mid-LIST request
  As a cluster operator
  I need the adapter to transparently refresh credentials when a LIST request returns 401
  So that momentary token expiry does not interrupt the user workflow

  Background:
    Given a cluster session "staging-us" is established with exec-credential provider "aws-eks-token"
    And the current bearer token has a remaining TTL of 1 second

  @chaos @cred
  Scenario: 401 mid-LIST triggers silent credential refresh and transparent retry
    Given a LIST request for "deployments" across all namespaces is in-flight
    When the API server returns HTTP 401 Unauthorized during the LIST response
    Then the adapter detects the 401 and suspends the LIST response
    And the adapter re-invokes the exec credential provider to obtain a fresh token
    And the LIST request is retried with the new token
    And the response is delivered to the UI without any error banner
    And the event "CredentialRefreshed" is recorded in telemetry with cause "http-401"

  @chaos @cred
  Scenario: Three consecutive exec-provider failures escalate to session Closed
    Given the bearer token has already expired
    And the exec credential provider is configured to fail with exit code 1
    When the adapter attempts credential re-resolution
    Then the first attempt fails and the adapter waits 2 seconds before the second attempt
    And the second attempt fails and the adapter waits 4 seconds before the third attempt
    And after three consecutive failures the session is marked "Closed" with reason "creds-expired"
    And the UI surfaces the error "Credential refresh failed — please re-authenticate"
    And no further API requests are dispatched on this session

  @chaos @cred
  Scenario: Credential refresh succeeds on second attempt and retries original request
    Given the exec credential provider fails once then succeeds
    When the adapter re-invokes the provider after a 401
    Then the adapter retries the provider a second time
    And the second invocation returns a valid token
    And the original request is retried successfully
    And the UI remains uninterrupted
