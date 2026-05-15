# DDD role: BehaviouralSpecification
# Bounded context: context_navigation
# References: ADR-0005, ADR-0025, ADR-0036

Feature: Context switch cancels watches on the outgoing cluster and loads the incoming cluster
  As an operator
  I want switching to a different cluster to cancel the active watches on the previous cluster
  So that resources from the previous cluster do not bleed into the new cluster's view

  Background:
    Given ClusterSessionActors for "cluster-a" and "cluster-b" are both in "connected" state
    And "cluster-a" is the active cluster with watch streams on "pods" and "deployments" in "Watching" state

  @happy @lifecycle
  Scenario: Switching to cluster-b cancels watches on cluster-a and loads cluster-b resources
    When the operator selects "cluster-b" in the context navigator
    Then the ContextNavigationState.activeClusterId changes to "cluster-b"
    And the watch streams for "pods" and "deployments" on "cluster-a" are cancelled (Task.cancel sent)
    And both watch streams for "cluster-a" transition to "Closed" state
    And the ResourceListReadModel for "cluster-a" is cleared
    And the ClusterSessionActor for "cluster-b" begins loading "pods" and "deployments" watches
    And the new watches for "cluster-b" transition to "Watching" state after the initial LIST completes
    And the ClusterSessionActor for "cluster-a" remains running (sessions persist on switch per ADR-0025)

  @happy @lifecycle
  Scenario: Returning to cluster-a restores its watches without a full relist from scratch
    Given the operator switched from "cluster-a" to "cluster-b" and now switches back to "cluster-a"
    When the operator selects "cluster-a" in the context navigator
    Then the ClusterSessionActor for "cluster-a" resumes watching resources for the active view
    And the view_state.json scroll position and namespace filter are restored from the in-memory session state
    And no "cold boot" relist from resourceVersion=0 is required if "cluster-a"'s session was kept alive

  @failure @lifecycle
  Scenario: Switch requested while the current cluster is in "degraded" state
    Given "cluster-a" is in "degraded" state due to a failed credential refresh
    When the operator switches to "cluster-b"
    Then the switch proceeds normally (degraded status does not block switching away)
    And the "cluster-a" session remains degraded in the background
    And no error from "cluster-a" propagates to the "cluster-b" view

  @race @lifecycle
  Scenario: Rapid back-and-forth switching between clusters does not leave stale watches open
    When the operator switches cluster-a → cluster-b → cluster-a in quick succession (within 500 ms)
    Then the final active cluster is "cluster-a"
    And all watches for "cluster-b" are cancelled before any "cluster-a" watches re-open
    And no duplicate watch streams exist for any resource kind in any cluster at the end of the sequence
