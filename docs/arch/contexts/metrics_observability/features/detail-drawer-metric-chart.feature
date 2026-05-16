# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (chart rendering orchestration), ReadModel (metric series)
# Context: metrics_observability
# Related ADRs: ADR-0058 (Detail-drawer Prometheus charts), ADR-0016 (Prometheus integration), ADR-0051 (Multi-cluster workspace)
Feature: Embedded Prometheus metric chart in resource detail drawer

  As an operator viewing a resource in the detail drawer,
  I want a compact CPU and memory chart to render inline
  so that I can assess resource pressure without navigating to the full metrics tab.

  Background:
    Given the active cluster context is "prod-aks"
    And a single detail drawer is open showing a Node named "node-worker-1"

  Scenario: Chart renders when Prometheus is configured and healthy
    Given a Prometheus endpoint is configured for cluster "prod-aks" with status "healthy"
    And the default time range is "1h"
    And the default series selection includes "cpu-usage", "cpu-requests", "cpu-allocatable", "cpu-capacity"
    When the detail drawer metrics panel initialises for Node "node-worker-1"
    Then MetricsObservabilityActor issues four range queries via PrometheusHTTPClient
    And each query uses the anchored label matcher form "=~\"^node-worker-1$\""
    And the chart renders four named series within 2 seconds of the drawer opening
    And the time-range picker shows segments "5m", "15m", "1h", "3h", "24h" with "1h" selected
    And a "View in Metrics" button is visible below the chart

  Scenario: Fallback message shown when Prometheus is not configured
    Given no Prometheus endpoint is configured for cluster "prod-aks"
    And PrometheusEndpointStatus is "not-configured"
    When the detail drawer metrics panel initialises for Node "node-worker-1"
    Then no Prometheus HTTP request is issued
    And the chart area is replaced by the static hint "Configure Prometheus (Settings > Metrics) to see charts here."
    And an "Open Settings" button navigating to Settings Metrics section is visible
    And no loading spinner or blank space is shown

  Scenario: Time-range switch updates the series
    Given a Prometheus endpoint is configured for cluster "prod-aks" with status "healthy"
    And the detail drawer metrics panel has already rendered a 1h chart for Node "node-worker-1"
    When the operator selects "24h" in the time-range picker
    Then MetricsObservabilityActor issues new range queries for the "24h" window
    And the chart re-renders with the updated series within 1 second of the selection
    And the previous 1h series is no longer shown

  Scenario: Drawer close cancels in-flight queries
    Given a Prometheus endpoint is configured for cluster "prod-aks" with status "healthy"
    And the detail drawer metrics panel has issued range queries that have not yet returned
    When the operator closes the detail drawer
    Then all in-flight Prometheus query tasks for that drawer are cancelled
    And no further Prometheus HTTP requests are issued for Node "node-worker-1" from that drawer
    And MetricsObservabilityActor releases the subscriptions associated with the closed drawer

  Scenario: Click-through opens full metrics tab
    Given a Prometheus endpoint is configured for cluster "prod-aks" with status "healthy"
    And the detail drawer metrics panel has rendered a chart for Node "node-worker-1"
    When the operator activates the "View in Metrics" button
    Then the full MetricsObservabilityView tab opens scoped to Node "node-worker-1" in cluster "prod-aks"
    And the tab time range matches the time range last selected in the drawer
    And the detail drawer remains open alongside the new tab
