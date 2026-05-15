# DDD role: BehaviouralSpecification
# Bounded context: analytics_dashboard
# References: ADR-0024, ADR-0034, ADR-0036

Feature: Pod deleted while its analytics widget is in view
  As an operator
  I want deleted pods to be clearly marked in the dashboard rather than causing errors
  So that historical data continues to be visible and the dashboard does not crash

  Background:
    Given the ClusterOverview dashboard is displaying metrics for Pod "api-0" in namespace "default"
    And the dashboard has a watch stream open on "pods" in namespace "default"

  @happy @lifecycle
  Scenario: Pod deleted — row marked as gone, historical data remains visible
    When a DELETED watch event arrives for "api-0"
    Then the #Deleted domain event is published to the ResourceListReadModel
    And the pod row for "api-0" in the dashboard is marked as "gone" with a visual indicator
    And any cached Prometheus widget data for "api-0" continues to render historical values
    And no error toast is shown (deletion is a normal lifecycle event)
    And the row is removed from the list after a configurable visibility TTL (default 30 seconds)

  @happy @lifecycle
  Scenario: Widget query for a deleted pod returns no new data — widget shows last known value
    Given "api-0" is marked as "gone" and the dashboard's 30-second refresh fires
    When the Prometheus range query for "api-0" cpu_usage returns an empty result set (pod no longer scraped)
    Then the widget retains the last non-empty data points it received before deletion
    And the widget shows a "stale data" indicator with the timestamp of the last known value
    And no Prometheus query error is raised

  @failure @lifecycle
  Scenario: Rapid pod churn — many DELETED events do not degrade dashboard performance
    Given 20 pods are deleted within 10 seconds (a rolling update scenario)
    When 20 DELETED watch events arrive in rapid succession
    Then each event is processed by the watch stream without dropping events (buffer not exceeded)
    And the UI batches the row removals into a single render pass
    And the dashboard frame rate remains acceptable (no jank from individual row removal animations)

  @lifecycle @happy
  Scenario: New pod with the same name replaces the gone row
    Given "api-0" is marked as "gone" in the dashboard
    When a new Pod "api-0" is created (e.g., by a StatefulSet rollout) and an ADDED event arrives
    Then the "gone" indicator is cleared from the row
    And the row displays the new pod's status and metrics
    And the historical data cache for the old "api-0" is cleared to avoid confusion
