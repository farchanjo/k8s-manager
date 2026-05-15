# DDD role: BehaviouralSpecification
# Bounded context: cluster_connectivity
# References: ADR-0002, ADR-0011, ADR-0018, ADR-0025

Feature: Credential expiry and refresh during an active watch session
  As a platform engineer
  I want bearer tokens to refresh transparently while watch streams stay live
  So that long-running sessions do not fail due to token expiry

  Background:
    Given a ClusterSessionActor for cluster "eks-prod" is in "connected" state
    And the cluster's kubeconfig context declares an exec credential plugin "aws"
    And one watch stream on "pods" in namespace "default" is in "Watching" state

  @happy @lifecycle
  Scenario: Token expiry triggers in-process refresh and watch resumes
    Given the session's credential cache holds a bearer token expiring in 5 seconds
    When 5 seconds elapse and the watch connection sends the next LIST or WATCH request
    Then the ClusterSessionActor invokes the AWSExecCredentialAdapter to obtain a fresh token
    And the credential cache is updated with the new token and its new expiry
    And the watch stream transitions briefly to "Relisting" and then back to "Watching"
    And no new HTTPClient or EventLoopGroup is created for "eks-prod"
    And the session lifecycle state remains "connected"
    And pool connections are reused without re-handshaking

  @happy @lifecycle
  Scenario: OIDC refresh token grant succeeds and watch continues with new token
    Given the cluster "oidc-cluster" uses an OIDC exec credential plugin
    And the current bearer token expires in 2 seconds
    And a valid refresh token is stored in Keychain under "com.archanjo.K8sManager.oidc.<clusterId>"
    When the token expiry clock advances by 2 seconds
    Then the OIDCExecCredentialAdapter exchanges the refresh token at the OIDC token endpoint
    And the credential cache is updated with the new access token
    And the watch stream on "pods" continues emitting events without interruption
    And no SessionDegraded event is emitted

  @failure @lifecycle
  Scenario: Refresh failure marks session as Degraded and watch pauses
    Given the session's credential cache holds a bearer token expiring in 3 seconds
    And the exec plugin is configured to return exit code 1 on the next invocation
    When 3 seconds elapse and the adapter attempts token refresh
    Then the adapter returns a CredentialError with the plugin's error output
    And the ClusterSessionActor transitions to lifecycle state "degraded"
    And a SessionDegraded event with reason "exec-plugin-failed" is published
    And the watch stream on "pods" transitions to "Backoff" state
    And the application surfaces a targeted affordance prompting the operator to fix the exec plugin

  @failure @lifecycle
  Scenario: Subsequent successful refresh recovers session from Degraded
    Given the ClusterSessionActor for "eks-prod" is in "degraded" state after a failed refresh
    And the exec plugin has been corrected and will succeed on the next invocation
    When the operator retries credential resolution via the settings affordance
    Then the AWSExecCredentialAdapter succeeds and returns a valid bearer token
    And the credential cache is populated with the new token
    And the ClusterSessionActor transitions from "degraded" to "connected"
    And the watch stream on "pods" transitions from "Backoff" to "Watching"
    And a SessionRecovered event is published
