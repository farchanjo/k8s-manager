Feature: Pod Detail Debug Dashboard

  The Pod Detail dashboard provides deep diagnostic visibility into a single
  Kubernetes pod. It renders CPU and memory time-series with request/limit
  overlays, OOMKilled correlation markers, restart count, network and disk
  I/O sparklines, a log error rate sparkline with a data link to the log
  viewer, an events timeline, and a container breakdown for multi-container
  pods. All widgets are always visible on PodDetailScope selection.

  Background:
    Given the operator has launched K8S-Manager
    And a Kubernetes context "production-aks" is selected and reachable
    And the metrics_observability context has a configured Prometheus endpoint
    And the operator has selected PodDetailScope for namespace "payments" pod "payments-api-7d9b8c-xk2pw"

  Scenario: CPU time-series renders with request and limit overlays
    Given the pod "payments-api-7d9b8c-xk2pw" has a CPU request of 250m and a CPU limit of 500m
    And Prometheus returns CPU usage data for the past 60 minutes
    When the "pod-cpu-line-chart" LineChart widget renders
    Then the chart displays three series: "usage" (blue), "request" (neutral dashed), "limit" (warning dashed)
    And the limit line is drawn at 0.5 cores across the entire time range
    And the request line is drawn at 0.25 cores across the entire time range

  Scenario: Memory time-series shows OOMKilled exit marker at the correct timestamp
    Given the pod "payments-api-7d9b8c-xk2pw" has a container restart with exit code 137 at "2026-05-15T03:17:22Z"
    And Prometheus returns memory usage data for the past 60 minutes
    When the "pod-mem-line-chart" LineChart widget renders
    Then the chart displays a vertical marker labeled "OOMKilled" at timestamp "2026-05-15T03:17:22Z"
    And the marker is colored "error"
    And the memory series shows a drop to zero at the OOMKilled marker timestamp

  Scenario: Restart count tile reflects actual pod restart history
    Given the pod "payments-api-7d9b8c-xk2pw" has a restart count of 4 reported by kubelet
    When the "pod-restart-count" Count widget renders
    Then the tile displays the value 4
    And the tile color is "warning" because restart count exceeds the threshold of 2
    And clicking the tile emits a DrillToEvents event for the pod with timeRangeMinutes = 60

  Scenario: Log error rate sparkline renders and links to log viewer on spike click
    Given the log stream for pod "payments-api-7d9b8c-xk2pw" contains error-pattern matches
    And the pattern "(?i)(error|exception|failed|panic|fatal)" matches 12 lines in the last 5 minutes
    When the "pod-log-error-rate" LogErrorRateWidget renders
    Then the sparkline shows a rising rate in the most recent 5-minute window
    When the operator clicks the spike at timestamp "2026-05-15T14:29:45Z"
    Then a DrillToLogs event is emitted with namespace = "payments", podName = "payments-api-7d9b8c-xk2pw", timestampRFC3339 = "2026-05-15T14:29:45Z"
    And the resource_browser log viewer opens positioned at that timestamp

  Scenario: Events timeline is filterable by source
    Given the pod "payments-api-7d9b8c-xk2pw" has 5 k8s_events and 2 mutation_audit entries in the last 60 minutes
    When the "pod-events-timeline" EventTimeline widget renders with sourceFilter = "all"
    Then 7 entries are displayed in chronological order
    When the operator changes the sourceFilter to "k8s_events"
    Then only the 5 Kubernetes object events are displayed

  Scenario: Container breakdown renders individual containers for a multi-container pod
    Given the pod "sidecar-demo-6f4b9-abc12" in namespace "monitoring" has two containers: "app" and "istio-proxy"
    And the operator selects PodDetailScope for this pod
    When the PodDetail dashboard renders
    Then the "pod-cpu-line-chart" widget shows separate series for "app" and "istio-proxy" containers
    And the "pod-mem-line-chart" widget shows separate series for "app" and "istio-proxy" containers
    And each container series is labeled with its container name

  Scenario: OOMKilled correlation hint surfaces queueing or memory contention context
    Given the pod "payments-api-7d9b8c-xk2pw" shows a P50-stable, P99-rising memory pattern in the 10 minutes before the OOMKilled event
    When the PodDetail dashboard renders after the OOMKilled event
    Then a LatencyDivergenceHint is surfaced as an inline annotation on the memory chart
    And the annotation reads "P99 memory rose 3x while P50 was stable — investigate memory pool exhaustion or GC pressure"
