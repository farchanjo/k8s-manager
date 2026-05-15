# DDD role: BehaviouralSpecification
# Bounded context: cluster_connectivity
# References: ADR-0007, ADR-0011, ADR-0025, ADR-0036

Feature: Cluster unreachable — session degradation and exponential backoff recovery
  As a platform engineer
  I want K8sManager to handle API server failures gracefully with exponential backoff
  So that transient network outages do not permanently break my session

  Background:
    Given a ClusterSessionActor for cluster "prod-us-east-1" is in "connected" state
    And the watch stream on "deployments" is in "Watching" state with lastKnownRV "12345"

  @failure @lifecycle
  Scenario: API server returns 503 — session degrades and backoff schedule starts
    When the API server returns HTTP 503 to the active WATCH request
    Then the watch stream transitions to "Backoff" state
    And the first backoff delay is between 200 and 300 milliseconds (250 ms ± 20%)
    And after the first backoff delay the adapter performs a full LIST (Phase 1 relist)
    And if the LIST also returns 503 the second backoff delay is between 400 and 600 milliseconds
    And the backoff schedule increments: 250, 500, 1000, 2000, 4000, 8000, 16000, cap 30000 ms
    And the ClusterSessionActor transitions to "degraded" lifecycle state
    And a SessionDegraded event with reason "api-server-503" is published

  @happy @lifecycle
  Scenario: API server recovers — session returns to connected and watch resumes
    Given the ClusterSessionActor is in "degraded" state after a 503 backoff sequence
    And the API server has recovered and is accepting requests
    When the current backoff interval elapses
    Then the adapter issues a LIST request that returns HTTP 200
    And the watch stream transitions through "Relisting" to "Watching"
    And the ClusterSessionActor transitions from "degraded" to "connected"
    And a SessionRecovered event is published
    And the consecutive error counter resets to zero

  @failure @lifecycle
  Scenario: Connection timeout — watch enters backoff without a 410 relist path
    Given the HTTPClient has a connection timeout of 30 seconds
    When the TCP connection to the API server times out (no response after 30 seconds)
    Then the adapter treats the timeout as a network error (not 410-Gone)
    And the watch stream enters "Backoff" with the first interval of 250 ms ± 20%
    And after the backoff the adapter issues a full LIST + WATCH (Phase 1 → Phase 2)
    And no Backoff-skip (immediate relist) occurs because this is not a 410-Gone error

  @failure @lifecycle
  Scenario: Task.cancel during backoff closes the watch stream cleanly
    Given the watch stream is in "Backoff" state waiting for the 4000 ms interval
    When Task.cancel is delivered to the watch stream task
    Then the Task.sleep for the backoff interval is interrupted immediately
    And the watch stream transitions directly to "Closed" state
    And no relist or WATCH request is issued after cancellation
    And the WatchStreamRegistry for "prod-us-east-1" removes the entry for "deployments"
