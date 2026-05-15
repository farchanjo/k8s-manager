# DDD role: ChaosScenario
# Bounded context: metrics_observability
# References: ADR-0016, ADR-0024, ADR-0027

Feature: Metric cardinality explosion — query returns 10k+ time series
  As an operator
  I want the metrics dashboard to gracefully truncate runaway high-cardinality
  query results to the top 100 series and warn me clearly
  So that a misbehaving or misconfigured Prometheus target cannot crash the dashboard

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Prometheus endpoint is active at "http://prometheus-operated.monitoring.svc:9090"
    And the operator has opened the "top-namespaces-cpu" widget in the ClusterOverview dashboard

  @chaos @failure
  Scenario: Prometheus query returns 10 000 time series — client truncates to top 100
    Given the Prometheus endpoint returns a matrix result with 10 000 series
         for the query "container_cpu_usage_seconds_total"
    When the PrometheusQueryActor receives and parses the response
    Then the domain service discards all but the top 100 series sorted by descending mean value
    And exactly 100 series are passed to the chart renderer
    And the chart renders successfully without crash or memory warning
    And a "Showing top 100 of 10 000 series — refine your query for detail" warning is displayed
         below the chart widget

  @chaos @failure
  Scenario: Cardinality warning shown persistently until query scope is narrowed
    Given the widget is displaying the "top 100 of 10 000 series" warning
    When the 30-second refresh cycle fires and the Prometheus query again returns >100 series
    Then the warning remains visible and updates its series count if it changes
    And the dashboard does not apply any automatic query narrowing on the operator's behalf
    And the "Refine query" affordance in the warning links to the per-cluster settings panel

  @chaos @performance
  Scenario: High-cardinality truncation does not degrade dashboard frame rate
    Given the Prometheus endpoint consistently returns 10 000 series per refresh cycle
    When 5 consecutive refresh cycles each return 10 000 series and are truncated to 100
    Then the SelfMonitoringSampler records frameTimeMs below 16 ms for each cycle
    And the performance_invariants.rego policy evaluates each sample as allowed
    And no RSS spike above the loaded ceiling of 600 MB is observed
