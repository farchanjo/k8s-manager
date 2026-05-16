# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (per-row metric updates), ReadModel (NodeMetricsRow)
# Context: resource_browser
# Related ADRs: ADR-0059 (Resource list row metric mini-bars), ADR-0016 (Prometheus integration), ADR-0058 (Detail-drawer Prometheus charts)
Feature: Node row live metric mini-bars

  Background:
    Given a cluster session is active with cluster id "cluster-a1b2"
    And the operator has navigated to the Node list view for that cluster

  Scenario: Bars render with Prometheus available
    Given a Prometheus endpoint is discovered for the cluster
    And the Prometheus instant query for CPU returns a vector with one sample per node
    And the Prometheus instant query for memory returns a vector with one sample per node
    And the Prometheus instant query for disk returns a vector with one sample per node
    When the Node list renders its first batch of rows
    Then each node row displays three mini-bars: CPU in blue, memory in magenta, disk in amber
    And the CPU bar fill width is proportional to cpu-usage divided by allocatable-cpu, clamped to the range 0.0 to 1.0
    And the memory bar fill width is proportional to memory-usage divided by allocatable-memory, clamped to the range 0.0 to 1.0
    And the disk bar fill width is proportional to disk-io-utilisation returned by the Prometheus query, clamped to the range 0.0 to 1.0
    And hovering over the CPU bar shows a tooltip with the label "CPU" and the formatted usage and capacity values
    And each bar has an accessibility label containing the metric name and the utilisation percentage

  Scenario: Bars freeze on cluster disconnect
    Given a Prometheus endpoint is discovered for the cluster
    And the Node list has rendered at least one batch of bars with non-zero values
    When the cluster session emits a disconnected state event
    Then all mini-bars in the Node list are rendered in a desaturated grey colour
    And no new Prometheus queries are issued for the disconnected cluster
    And the tooltip on each greyed bar reads "cluster disconnected — metrics frozen"
    And the last known metric values remain visible in the bar dimensions
    When the cluster session reconnects
    Then the bars return to their colour-coded state on the next successful Prometheus batch query

  Scenario: Kubelet fallback when Prometheus is absent
    Given no Prometheus endpoint is reachable for the cluster
    When the Node list renders its first batch of rows
    Then NodeMetricsRefreshActor issues requests to the kubelet proxy path for each visible node
    And the kubelet proxy path used is "/api/v1/nodes/<node-name>/proxy/metrics/resource"
    And each node row displays a CPU mini-bar and a memory mini-bar
    And no disk mini-bar is rendered for any node row
    And hovering over the position where the disk bar would appear shows a tooltip reading "disk unavailable without Prometheus"

  Scenario: Off-viewport rows pause queries
    Given a Prometheus endpoint is discovered for the cluster
    And the Node list contains more rows than fit in the visible viewport
    When the operator scrolls the Node list so that row "node-faraway" is no longer visible
    Then "node-faraway" is removed from the active node-name set in NodeMetricsRefreshActor
    And the next batch query does not include a label selector for "node-faraway"
    When the operator scrolls back so that "node-faraway" becomes visible again
    Then "node-faraway" is added back to the active node-name set in NodeMetricsRefreshActor
    And the subsequent batch query includes "node-faraway" in its label selector

  Scenario: Capacity-relative colour saturation reflects utilisation intensity
    Given a Prometheus endpoint is discovered for the cluster
    And a node "node-heavy" reports CPU utilisation at 92 percent of allocatable capacity
    And a node "node-light" reports CPU utilisation at 20 percent of allocatable capacity
    When the Node list renders the rows for "node-heavy" and "node-light"
    Then the CPU mini-bar for "node-heavy" is rendered in red to signal pressure above the 90 percent threshold
    And the CPU mini-bar for "node-light" is rendered in blue with saturation proportional to its 20 percent utilisation
    And the saturation of the "node-light" CPU bar is lower than the saturation of a bar at 80 percent utilisation
