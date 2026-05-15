# DDD role: BehaviouralSpecification
# Bounded context: context_navigation
# References: ADR-0005, ADR-0026
# CUE schema: contexts/context_navigation/schemas/recent_context.cue

Feature: Pinned clusters and recent history persistence across launches
  As an operator managing many clusters
  I want pinned clusters and my recent visit history to survive app restarts
  So that I can quickly navigate back to frequently used clusters

  Background:
    Given the operator has been using K8sManager with 15 different cluster contexts

  @happy @lifecycle
  Scenario: Pinning 3 clusters and visiting 10 — relaunch shows pinned + last 5 recents
    Given the operator has pinned "prod-us-east-1", "prod-eu-west-1", and "staging-eu-west"
    And the operator has visited "dev-local", "qa-1", "qa-2", "perf-test", "sandbox-1", "sandbox-2", and "sandbox-3" in that order
    When the application quits and relaunches
    Then the context navigator shows the 3 pinned clusters at the top of the list
    And below the pinned section the 5 most recently visited clusters are shown: "sandbox-3", "sandbox-2", "sandbox-1", "perf-test", "qa-2"
    And clusters visited earlier ("qa-1", "dev-local", and others) are NOT shown in the recents section
    And the recent history is loaded from "storage.sqlite3" on launch

  @happy @lifecycle
  Scenario: Pinning a cluster that is already in recents removes it from recents
    Given "staging-eu-west" appears in the recents list
    When the operator pins "staging-eu-west"
    Then "staging-eu-west" moves to the pinned section
    And it is removed from the recents list (no duplicate entry)
    And the recents list shows the next most recent cluster in its place

  @failure @lifecycle
  Scenario: Unpinning a cluster adds it back to recents in its correct chronological position
    Given the operator unpins "prod-us-east-1"
    When the ContextNavigationState processes the unpin action
    Then "prod-us-east-1" moves from pinned to the most recent position in the recents list (it was the last cluster used)
    And the recents list trims to at most 5 entries

  @persistence @lifecycle
  Scenario: Recent visit order is persisted atomically after each cluster switch
    When the operator switches from "cluster-a" to "cluster-b"
    Then the recent visit record for "cluster-b" is written to "storage.sqlite3" within 5 seconds
    And if the application crashes immediately after, the next launch still shows "cluster-b" in the recents list
