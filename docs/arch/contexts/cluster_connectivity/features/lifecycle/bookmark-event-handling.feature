# DDD role: BehaviouralSpecification
# Bounded context: cluster_connectivity
# References: ADR-0036

Feature: BOOKMARK event advances RV without cache mutation
  As a platform engineer
  I want BOOKMARK events to silently update the tracked resource version
  So that subsequent WATCH reconnects use a fresh RV and avoid unnecessary 410-Gone responses

  Background:
    Given a ClusterSessionActor for cluster "prod-us-east-1" is in "connected" state
    And a watch stream on "pods" is in "Watching" state with lastKnownRV "9000"
    And the WATCH was opened with allowWatchBookmarks=true

  @happy @lifecycle
  Scenario: BOOKMARK event updates lastKnownRV without domain notification
    When the API server emits a BOOKMARK event with object.metadata.resourceVersion "9200"
    Then the adapter atomically updates WatchStreamState.lastKnownRV to "9200"
    And no #Replaced, #Added, #Modified, or #Deleted event is emitted to the domain actor
    And no object in the local domain cache is changed
    And the watch stream remains in "Watching" state

  @happy @lifecycle
  Scenario: Subsequent WATCH reconnect uses the BOOKMARK RV
    Given lastKnownRV was advanced to "9200" by a prior BOOKMARK event
    When the current WATCH stream closes at the 300-second server-initiated timeout
    Then the adapter opens a new WATCH with resourceVersion="9200"
    And the adapter does NOT issue a full LIST before opening the new WATCH
    And the watch stream transitions briefly through "Backoff" (zero-delay reconnect) to "Watching"

  @happy @lifecycle
  Scenario: Multiple BOOKMARK events in sequence advance RV monotonically
    Given the watch stream has received BOOKMARK events advancing RV through "9200", "9400", "9600"
    When the API server sends a BOOKMARK with resourceVersion "9600"
    Then lastKnownRV is "9600"
    And a subsequent ADDED event with resourceVersion "9601" is processed normally
    And lastKnownRV advances to "9601" after the ADDED event

  @failure @lifecycle
  Scenario: BOOKMARK with lower RV than lastKnownRV is ignored
    Given lastKnownRV is "9200"
    When the API server sends a BOOKMARK event with resourceVersion "9100"
    Then the adapter ignores the BOOKMARK and does not update lastKnownRV
    And lastKnownRV remains "9200"
    And a warning log entry notes the out-of-order BOOKMARK
