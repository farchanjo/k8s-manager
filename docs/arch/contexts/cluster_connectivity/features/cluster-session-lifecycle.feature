# DDD role: BehaviouralSpecification
Feature: Cluster session lifecycle management

  As a platform engineer using K8sManager
  I want each cluster to have its own isolated session with a dedicated HTTPClient pool
  So that switching between clusters is predictable, state is never shared across clusters,
  and teardown of one session never affects other active sessions.

  Background:
    Given the application has started
    And no ClusterSessionActor instances are running

  Scenario: Opening a cluster creates an isolated session with a dedicated HTTPClient pool
    Given a kubeconfig context "prod-us-east-1" is registered with a valid CA and bearer token
    When the operator activates cluster "prod-us-east-1"
    Then a ClusterSessionActor is spawned for "prod-us-east-1"
    And the session lifecycle state transitions to "connecting" then "connected"
    And the session owns an HTTPClient instance that is exclusive to "prod-us-east-1"
    And the session owns an EventLoopGroup instance that is exclusive to "prod-us-east-1"
    And the session owns an empty credential cache scoped to "prod-us-east-1"
    And a SessionOpened event is published on the session's event stream

  Scenario: Idle connection pool reaping within an active session
    Given a ClusterSessionActor for cluster "staging-eu-west" is in "connected" state
    And the session has previously issued 5 HTTP requests leaving 3 idle connections in the pool
    When 46 seconds elapse without any new HTTP request against "staging-eu-west"
    Then the HTTPClient pool for "staging-eu-west" reports 0 idle connections
    And the session lifecycle state remains "connected"
    And the EventLoopGroup for "staging-eu-west" remains running
    And a PoolStatsSnapshot event is published showing idleConnections equals 0

  Scenario: Active switch between two clusters keeps both session pools alive
    Given a ClusterSessionActor for cluster "prod-us-east-1" is in "connected" state with 4 idle connections
    And a ClusterSessionActor for cluster "staging-eu-west" is in "connected" state with 2 idle connections
    When the operator switches the active context from "prod-us-east-1" to "staging-eu-west"
    Then the active context identifier becomes "staging-eu-west"
    And the ClusterSessionActor for "prod-us-east-1" remains in "connected" state
    And the HTTPClient pool for "prod-us-east-1" still holds 4 idle connections
    And the ClusterSessionActor for "staging-eu-west" remains in "connected" state
    And the HTTPClient pool for "staging-eu-west" still holds 2 idle connections
    And no SessionTerminated event is published for either cluster

  Scenario: Manual disconnect terminates the session and closes the pool
    Given a ClusterSessionActor for cluster "dev-local" is in "connected" state
    And the session has 1 active watch stream and 2 idle HTTP connections
    When the operator manually disconnects cluster "dev-local"
    Then the ClusterSessionActor for "dev-local" transitions to lifecycle state "terminating"
    And the watch stream registry for "dev-local" is emptied
    And the HTTPClient for "dev-local" is shut down
    And the EventLoopGroup for "dev-local" is stopped
    And a SessionTerminated event with reason "operator-requested" is published
    And no other ClusterSessionActor is affected

  Scenario: Credential cache refresh after exec-plugin token rotation
    Given a ClusterSessionActor for cluster "eks-prod" is in "connected" state
    And the session's credential cache holds a bearer token that expires in 10 seconds
    When the token expiry clock advances by 10 seconds
    Then ClusterSessionActor for "eks-prod" invokes the exec plugin to obtain a fresh token
    And the credential cache is updated with the new token
    And no new HTTPClient or EventLoopGroup is created for "eks-prod"
    And the session lifecycle state remains "connected"
    And the HTTPClient pool connections are reused without re-handshaking

  Scenario: Maximum of 8 simultaneous cluster sessions is enforced
    Given ClusterSessionActors are running for clusters "c1" through "c8"
    And each session is in "connected" state
    When the operator attempts to activate a 9th cluster "c9"
    Then a SessionCapExceeded event is emitted
    And no ClusterSessionActor is spawned for "c9"
    And the application presents a prompt asking the operator to close one of the 8 existing sessions
    And all 8 existing sessions remain in "connected" state

  Scenario: Session transitions to degraded when exec plugin fails but pool remains live
    Given a ClusterSessionActor for cluster "oidc-cluster" is in "connected" state
    And the cluster's kubeconfig context uses an exec credential plugin
    When the exec plugin process exits with a non-zero return code during a credential refresh
    Then the session lifecycle state for "oidc-cluster" transitions to "degraded"
    And a SessionDegraded event with reason "exec-plugin-failed" is published
    And the HTTPClient for "oidc-cluster" remains alive
    And the EventLoopGroup for "oidc-cluster" remains running
    And existing watch streams in the registry are not closed
    And the application surfaces a targeted affordance prompting the operator to fix the exec plugin
