# DDD role: BehaviouralSpecification
# Bounded context: analytics_dashboard
# References: ADR-0024
# CUE schema: contexts/analytics_dashboard/schemas/drilldown_event.cue

Feature: Drill-down from heatmap widget to log view at a specific timestamp
  As an operator
  I want to click on a bar in a latency heatmap and navigate to the correlated logs at that timestamp
  So that I can investigate spikes in the metrics directly without switching tools

  Background:
    Given the ClusterOverview dashboard is displaying a latency heatmap for namespace "production"
    And the heatmap shows a spike at timestamp T=2026-05-15T14:23:00Z

  @happy @lifecycle
  Scenario: Click on heatmap bar navigates to filtered log view at spike timestamp
    When the operator clicks on the bar at T=2026-05-15T14:23:00Z in the heatmap
    Then a DrilldownEvent is emitted with timestamp "2026-05-15T14:23:00Z" and source "latency-heatmap"
    And the navigation context transitions to the log view for namespace "production"
    And the log view is pre-filtered with sinceTime="2026-05-15T14:22:00Z" and untilTime="2026-05-15T14:24:00Z"
    And the operator sees log entries surrounding the spike timestamp

  @failure @lifecycle
  Scenario: No logs available for the drill-down timestamp — informative empty state
    Given no Pod logs are available in the time window around T=2026-05-15T14:23:00Z
    When the operator clicks the heatmap bar and navigates to the log view
    Then the log view shows "No logs found in the selected time window"
    And a suggestion appears: "Try expanding the time window or checking namespace 'kube-system'"
    And the filter controls are shown so the operator can adjust the query

  @happy @lifecycle
  Scenario: Drill-down from widget preserves original dashboard scroll position
    Given the operator has scrolled the dashboard to show the heatmap widget at the bottom
    When the operator drills down and then presses the browser-style back button in the navigation
    Then the dashboard is restored with the same scroll position and the heatmap widget visible
    And the heatmap data is still rendered (not refetched from Prometheus on back-navigation)

  @lifecycle @happy
  Scenario: Multiple drill-down events from different widgets are handled independently
    Given the operator drills down from the CPU heatmap to logs for pod "api-0"
    When the operator also drills down from the memory heatmap to logs for pod "worker-0"
    Then two log views are open simultaneously, each with their own independent filters
    And closing one log view does not affect the other
