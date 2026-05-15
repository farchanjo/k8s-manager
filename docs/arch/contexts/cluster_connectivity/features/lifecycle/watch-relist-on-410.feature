# DDD role: BehaviouralSpecification
# Bounded context: cluster_connectivity
# References: ADR-0036

Feature: Watch stream 410-Gone recovery — full LIST then WATCH
  As a platform engineer
  I want stale resource-version watch errors to trigger an immediate relist
  So that my resource cache is always coherent and never silently diverged

  Background:
    Given a ClusterSessionActor for cluster "prod-us-east-1" is in "connected" state
    And a watch stream on "pods" in namespace "default" is in "Watching" state
    And lastKnownRV is "9000"

  @happy @lifecycle
  Scenario: 410-Gone triggers immediate relist without entering Backoff
    When the API server emits an ERROR event with object.code equal to 410
    Then the adapter closes the current WATCH HTTP/2 stream
    And the adapter emits an #Invalidated event to the domain actor before any other event
    And the watch stream transitions to "Relisting" (NOT to "Backoff")
    And the adapter immediately issues a LIST with resourceVersion=0 (no backoff delay)
    And the LIST returns HTTP 200 with a new resourceVersion "12500"
    And lastKnownRV is updated to "12500"
    And a #Replaced event is emitted to the domain actor with the full fresh object list
    And the adapter opens a new WATCH with resourceVersion="12500" and allowWatchBookmarks=true
    And the watch stream transitions to "Watching" with the new lastKnownRV

  @failure @lifecycle
  Scenario: 410-Gone followed by failed relist enters Backoff
    When the API server emits an ERROR event with object.code equal to 410
    And the subsequent LIST request fails with a TCP connection reset
    Then the watch stream transitions from "Relisting" to "Backoff"
    And the first backoff delay applies (250 ms ± 20%)
    And after the delay the adapter retries the full LIST + WATCH sequence

  @idempotency @lifecycle
  Scenario: Events with RV at or below lastKnownRV are silently discarded after relist
    Given a relist completed with lastKnownRV "12500"
    And the new WATCH stream opens immediately
    When the first event from the WATCH stream has resourceVersion "12498" (older than lastKnownRV)
    Then the adapter discards the event without emitting it to the domain actor
    And lastKnownRV remains "12500"
    And the next event with resourceVersion "12501" is processed normally

  @race @lifecycle
  Scenario: Concurrent LIST pages all complete before WATCH opens
    Given the LIST response for "pods" has metadata.continue set (multi-page result)
    When the adapter follows the continuation token across 3 pages
    Then lastKnownRV is captured only from the final page (the authoritative value)
    And the WATCH stream opens only after all pages have been consumed
    And the #Replaced event contains the merged object list from all pages
