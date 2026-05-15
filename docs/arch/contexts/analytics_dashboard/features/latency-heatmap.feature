Feature: Latency Heatmap on Service Detail

  The Service Detail dashboard includes a Heatmap widget that renders Prometheus
  histogram bucket data as p50/p95/p99 time columns. The heatmap is always
  visible on ServiceDetailScope selection and provides data links: clicking a
  column drills down to the log viewer at that timestamp. When P50 is stable but
  P99 rises, the widget surfaces a queueing or pool exhaustion hint.

  Background:
    Given the operator has launched K8S-Manager
    And a Kubernetes context "production-aks" is selected and reachable
    And the metrics_observability context has a configured Prometheus endpoint
    And the Prometheus endpoint exposes histogram metric "http_request_duration_seconds" for service "payments-gateway" in namespace "payments"
    And the operator has selected ServiceDetailScope for namespace "payments" service "payments-gateway"

  Scenario: Heatmap renders p50, p95, and p99 simultaneously on ServiceDetail scope
    Given Prometheus returns histogram bucket data for "http_request_duration_seconds" over the last 60 minutes
    When the "svc-latency-heatmap" HeatmapWidget renders
    Then three percentile bands are visible: p50 (bottom), p95 (middle), p99 (top)
    And each band is color-coded: p50 green (healthy), p95 blue (info), p99 yellow or red based on threshold
    And no single-percentile rendering is permitted — all three bands are present simultaneously

  Scenario: Bimodal distribution is visible when traffic splits across fast and slow response paths
    Given the histogram data shows two response time clusters: one peak at 20ms and another at 250ms
    When the "svc-latency-heatmap" HeatmapWidget renders
    Then the heatmap columns show two distinct color density bands within the same time window
    And the p95 band is significantly higher than the p50 band in those columns
    And the heatmap legend indicates the value range of each percentile band

  Scenario: Clicking a heatmap column drills down to logs at that timestamp
    Given the heatmap shows a high-latency spike in the column for timestamp "2026-05-15T11:05:00Z"
    When the operator clicks the column at timestamp "2026-05-15T11:05:00Z"
    Then a DrillToLogs event is emitted with timestampRFC3339 = "2026-05-15T11:05:00Z"
    And the namespace is "payments" and the podName selector is "app=payments-gateway"
    And the resource_browser log viewer opens positioned at "2026-05-15T11:05:00Z"

  Scenario: P50 stable and P99 rising triggers queueing investigation hint
    Given the histogram data shows that p50 latency remains at 18ms for 30 minutes
    And p99 latency rises from 80ms to 420ms over the same 30 minutes
    When the HeatmapWidget evaluates the percentile divergence
    Then a LatencyDivergenceHint is rendered as an inline banner on the heatmap widget
    And the banner reads "P50 stable while P99 rose 5x — investigate queueing, connection pool exhaustion, or GC pauses"
    And the banner color is "warning"

  Scenario: Histogram bucket aggregation uses pre-bucketed Prometheus data
    Given the Prometheus endpoint exposes "http_request_duration_seconds_bucket" with standard bucket boundaries
    When WidgetQueryDispatchService builds the heatmap query via MetricsQueryPort
    Then the query uses histogram_quantile(0.50, ...), histogram_quantile(0.95, ...), and histogram_quantile(0.99, ...) on the pre-bucketed metric
    And the query step_seconds matches the heatmap column width derived from rangeMinutes and the display width
    And no client-side percentile computation is performed — all aggregation is pushed to Prometheus
