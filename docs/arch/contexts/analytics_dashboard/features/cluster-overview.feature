Feature: Cluster Overview Dashboard

  The Cluster Overview dashboard is always visible when the operator selects
  the "Cluster Overview" scope in the sidebar. It aggregates node status, pod
  phase distribution, cluster-wide CPU and memory utilization, deployment
  availability, top namespaces by resource consumption, and recent events.
  All widgets render immediately on scope selection using the ClusterOverview
  ScopePreset default layout.

  Background:
    Given the operator has launched K8S-Manager
    And a Kubernetes context "production-aks" is selected and reachable
    And the metrics_observability context has a configured Prometheus endpoint

  Scenario: Dashboard is always visible on scope selection
    When the operator selects "Cluster Overview" in the sidebar scope picker
    Then the analytics dashboard panel is visible without any additional click
    And the panel displays the ClusterOverview preset layout with all default widget slots rendered
    And no loading spinner persists for more than 3 seconds per widget

  Scenario: Auto-refresh occurs every 30 seconds with a visible indicator
    Given the ClusterOverview dashboard is displayed
    When 30 seconds elapse since the last data fetch
    Then all widget data is re-queried from the upstream ports
    And a subtle animated refresh indicator appears in the dashboard header during the query
    And the indicator disappears within 2 seconds of the fetch completing

  Scenario: Nodes Ready and NotReady count tiles reflect cluster state
    Given the cluster has 8 nodes where 7 report condition Ready=True and 1 reports Ready=False
    When the ClusterOverview dashboard renders the "nodes-ready-count" widget
    Then the Count widget displays the value 7
    And the tile color is "healthy" because all ready count exceeds 0
    And a separate "nodes-not-ready-count" indicator shows 1 with color "error"

  Scenario: Pods stacked bar reflects Running, Pending, and Failed pod phases
    Given the cluster has 120 pods: 110 Running, 7 Pending, 3 Failed
    When the ClusterOverview dashboard renders the "pods-phase-stacked-bar" widget
    Then the StackedBar displays three segments in order: Running (green), Pending (yellow), Failed (red)
    And the Running segment occupies the proportionally largest portion of the bar
    And the Failed segment count label shows 3 with color "error"

  Scenario: Top 5 namespaces by CPU are listed in descending order
    Given Prometheus returns CPU usage data for 12 namespaces in the cluster
    When the "top-namespaces-cpu" TopList widget renders
    Then exactly 5 namespaces are listed
    And they are ordered from highest to lowest CPU consumption
    And clicking a namespace row emits a DrillToScope event targeting NamespaceDetailScope for that namespace

  Scenario: Clicking a CPU sparkline spike drills down to NamespaceDetail
    Given the ClusterOverview dashboard is displayed
    And the "cluster-cpu-sparkline" Sparkline widget shows a usage spike at timestamp "2026-05-15T14:32:00Z"
    When the operator clicks the spike at timestamp "2026-05-15T14:32:00Z"
    Then a DrillToScope DrillDownEvent is emitted with targetScope = NamespaceDetailScope
    And the sidebar scope picker updates to show "Namespace Detail"
    And the NamespaceDetail dashboard renders for the namespace with the highest CPU at that timestamp

  Scenario: Widgets degrade gracefully when Prometheus is not configured
    Given the metrics_observability context has no configured Prometheus endpoint for "production-aks"
    When the ClusterOverview dashboard renders
    Then all Prometheus-backed widgets (cluster-cpu-sparkline, cluster-mem-sparkline, top-namespaces-cpu, top-namespaces-mem) display a degraded state placeholder
    And each degraded widget shows the hint text "Prometheus not configured — connect an endpoint in Settings"
    And widgets backed exclusively by cluster_connectivity (nodes-ready-count, pods-phase-stacked-bar, namespace-count) render with live data unaffected
