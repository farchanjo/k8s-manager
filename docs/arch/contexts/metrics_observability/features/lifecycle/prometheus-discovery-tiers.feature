# DDD role: BehaviouralSpecification
# Bounded context: metrics_observability
# References: ADR-0016

Feature: Prometheus endpoint discovery — three-tier fallback pipeline
  As an operator
  I want Prometheus to be discovered automatically without manual configuration for common deployments
  So that I can see cluster metrics immediately after connecting to a cluster

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And no manual Prometheus override has been configured for this cluster

  @happy @lifecycle
  Scenario: Tier 1 well-known endpoint probed and succeeds — used immediately
    When the PrometheusDiscoveryService runs for "prod-us-east-1"
    Then a HEAD request is sent to "http://prometheus-operated.monitoring.svc:9090/-/healthy" via the cluster's API server proxy path
    And the probe returns HTTP 200
    And the PrometheusEndpointRepository stores the endpoint with discoverySource "well_known"
    And no further discovery tiers are executed
    And the metrics dashboard activates using the well_known endpoint

  @happy @lifecycle
  Scenario: Tier 1 fails, Tier 2 auto_label scan discovers Prometheus via Service label
    Given the well-known probe returns HTTP 503 (Prometheus not at default location)
    And a Service "prometheus-custom" in namespace "monitoring" has label "app.kubernetes.io/name=prometheus"
    And the Service has a TCP port named "web" on port 9090
    When the discovery pipeline continues to Tier 2
    Then a LIST of all Services is issued once (shared for Tier 2 and Tier 3)
    And the first matching Service sorted by (namespace ASC, name ASC) is selected
    And the endpoint is stored with discoverySource "auto_label"
    And the metrics dashboard activates using the auto_label endpoint

  @happy @lifecycle
  Scenario: Tier 2 fails, Tier 3 auto_annotation discovers via prometheus.io/scrape=true
    Given no Service has the "app.kubernetes.io/name=prometheus" label
    And a Service "prom-agent" has annotation "prometheus.io/scrape=true" and port 9090
    When the discovery pipeline continues to Tier 3 (using the same Service list from Tier 2)
    Then the first matching Service is selected and stored with discoverySource "auto_annotation"

  @failure @lifecycle
  Scenario: All three tiers produce no candidates — dashboard shows empty state
    Given no Services match any of the three discovery criteria
    When the discovery pipeline completes
    Then the metrics dashboard shows an empty-state view
    And the hint message references kube-prometheus-stack installation steps
    And a "Configure manual endpoint" affordance is shown in the settings
    And no unhandled error is thrown
