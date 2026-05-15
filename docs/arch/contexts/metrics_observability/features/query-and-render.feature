Feature: Query Prometheus and render metric charts in K8sManager

  As an operator viewing resources in K8sManager,
  I want curated PromQL dashboards to render automatically
  so that I can diagnose CPU, memory, network, and API-server health without writing PromQL.

  Background:
    Given a PrometheusEndpoint with status "healthy" is active for the current cluster context
    And the endpoint url is "http://prometheus-operated.monitoring.svc:9090"
    And auth_strategy is "none"
    And the operator has selected a Pod named "api-server-7d4b9c" in namespace "default" in the resource browser

  Scenario: Instant CPU query for a Pod returns an instant vector result
    Given the operator opens the metrics panel for Pod "api-server-7d4b9c"
    And the panel requests a current CPU reading using query id "pod_cpu_usage_seconds" in instant mode
    When the HTTP client sends a GET to "/api/v1/query" with the substituted PromQL expression
    Then the Prometheus endpoint responds with resultType "vector" and one or more samples
    And the metrics panel displays the current CPU value in millicores
    And the request completes within 1 second of the panel opening

  Scenario: Range query for 60 minutes with step 30s renders a line chart
    Given the operator opens the metrics panel for Pod "api-server-7d4b9c"
    And the default range is the last 60 minutes with step 30 seconds
    When the HTTP client sends a GET to "/api/v1/query_range" with start, end, and step parameters
    Then the Prometheus endpoint responds with resultType "matrix" containing one or more series
    And each series contains at most 120 data points
    And the metrics panel renders a line chart with time on the x-axis and CPU seconds on the y-axis
    And the chart renders within 1 second of the data being received

  Scenario: Query returns empty result set — no Prometheus data for this Pod
    Given the cluster has Prometheus installed and healthy
    And the Pod "api-server-7d4b9c" was created 10 seconds ago
    And no scraped metric data yet exists for it in Prometheus
    When the range query "/api/v1/query_range" returns resultType "matrix" with an empty series list
    Then the metrics panel shows an actionable empty-state message
    And the message explains that no data is available for the selected time window
    And the message suggests widening the time range or waiting for the next scrape interval
    And no unhandled error or crash occurs

  Scenario: Prometheus endpoint returns 503 — endpoint marked unreachable
    Given the Prometheus endpoint is temporarily overloaded
    When the HTTP client receives HTTP 503 from "/api/v1/query_range"
    Then the PrometheusEndpoint status is updated to "unreachable"
    And the metrics panel shows a connectivity error banner
    And the banner includes the HTTP status code 503
    And the banner provides a "Retry" button that re-issues the query on tap
    And no cached stale data from a previous successful query is silently shown as current

  Scenario: Bearer token expires during a query — re-authentication via KubernetesApiPort
    Given auth_strategy is "bearer_inherit"
    And the current bearer token in the KubernetesSession has expired
    When the HTTP client sends the range query and receives HTTP 401 from the endpoint
    Then K8sManager triggers a re-authentication pass through KubernetesApiPort
    And a fresh bearer token is acquired from the cluster credential
    And the HTTP client retries the original range query with the new token
    And the chart renders successfully on the retry
    And the PrometheusEndpoint status remains "healthy" after the successful retry

  Scenario: Curated CPU query renders correctly for the Pod selected in the resource browser
    Given the curated query "pod_cpu_usage_seconds" has placeholders {namespace} and {podName}
    And the resource browser has Pod "api-server-7d4b9c" in namespace "default" selected
    When the metrics panel activates for this Pod
    Then the PromQL expression is resolved to include namespace="default" and pod=~"api-server-7d4b9c"
    And the HTTP client sends the resolved expression to "/api/v1/query_range"
    And the resulting series is displayed in the CPU chart section of the metrics panel
    And switching the selected Pod in the resource browser to "worker-pod-8f2c1b" reloads the chart
    And the new chart displays data for "worker-pod-8f2c1b" only

  Scenario: Query result exceeds 200 data points — downsampled before rendering
    Given the operator sets a custom time range of 24 hours with step 10 seconds
    And this range produces 8640 data points per series
    When the HTTP client receives the matrix result with 8640 points in a series
    Then the domain service downsamples the series to exactly 200 points using uniform index sampling
    And the chart receives exactly 200 points per series
    And no data points are passed directly to the chart renderer without downsampling when count exceeds 200
