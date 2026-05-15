Feature: Auto-discover Prometheus endpoint for a Kubernetes cluster

  As an operator connecting K8sManager to a Kubernetes cluster,
  I want Prometheus to be discovered automatically where possible
  so that metrics dashboards are available without manual configuration.

  Background:
    Given the operator has connected to a cluster context with id "ctx-abc123"
    And the cluster context becomes active

  Scenario: Cluster with kube-prometheus-stack detected via well-known in-cluster address
    Given the cluster has kube-prometheus-stack installed with default chart values
    And the endpoint "http://prometheus-operated.monitoring.svc:9090/-/healthy" returns HTTP 200
    When the discovery pipeline runs for context "ctx-abc123"
    Then a PrometheusEndpoint is created with discovery_source "well_known"
    And the endpoint url is "http://prometheus-operated.monitoring.svc:9090"
    And the endpoint status is "healthy"
    And no manual configuration is required from the operator

  Scenario: Cluster with Prometheus Service identified by app label
    Given the cluster does not have the well-known kube-prometheus-stack endpoint reachable
    And a Service exists in namespace "monitoring" with label "app.kubernetes.io/name=prometheus"
    And the Service has a TCP port named "web" on port 9090
    And the cluster IP of the Service is "10.96.20.5"
    When the discovery pipeline runs for context "ctx-abc123"
    Then a PrometheusEndpoint is created with discovery_source "auto_label"
    And the endpoint url is "http://10.96.20.5:9090"
    And the endpoint status is "unknown" until the health probe completes

  Scenario: Cluster with Prometheus Service identified by scrape annotation
    Given the cluster does not have the well-known kube-prometheus-stack endpoint reachable
    And no Service has the label "app.kubernetes.io/name=prometheus"
    And a Service exists in namespace "observability" with annotation "prometheus.io/scrape=true"
    And the Service has port 9090 exposed
    When the discovery pipeline runs for context "ctx-abc123"
    Then a PrometheusEndpoint is created with discovery_source "auto_annotation"
    And the endpoint namespace is "observability"
    And the metrics panel becomes enabled for the cluster

  Scenario: No Prometheus candidate found in the cluster
    Given the cluster does not have the well-known kube-prometheus-stack endpoint reachable
    And no Service matches the label "app.kubernetes.io/name=prometheus"
    And no Service has the annotation "prometheus.io/scrape=true"
    When the discovery pipeline runs for context "ctx-abc123"
    Then no PrometheusEndpoint is stored for context "ctx-abc123"
    And the metrics panel shows an empty-state view
    And the empty-state view contains a hint with the text "Install kube-prometheus-stack"
    And the empty-state view contains a link to the kube-prometheus-stack installation documentation
    And the settings panel shows a URL input field to enter a Prometheus endpoint manually

  Scenario: Multiple Prometheus candidates found — first sorted candidate becomes default
    Given the cluster does not have the well-known kube-prometheus-stack endpoint reachable
    And a Service "prometheus-a" exists in namespace "monitoring" with label "app.kubernetes.io/name=prometheus"
    And a Service "prometheus-b" exists in namespace "infra" with label "app.kubernetes.io/name=prometheus"
    When the discovery pipeline runs for context "ctx-abc123"
    Then two PrometheusEndpoint records are stored for context "ctx-abc123"
    And the active endpoint corresponds to Service "prometheus-b" in namespace "infra"
    And the settings UI lists both candidates as selectable alternatives
    And the operator can switch the active endpoint to "prometheus-a" in namespace "monitoring"

  Scenario: Manual override URL takes precedence over all auto-detection results
    Given the operator has entered the URL "https://prometheus.example.com" in per-cluster settings for context "ctx-abc123"
    And auto-discovery would detect the well-known kube-prometheus-stack endpoint
    When the discovery pipeline runs for context "ctx-abc123"
    Then the active PrometheusEndpoint has discovery_source "manual_override"
    And the active endpoint url is "https://prometheus.example.com"
    And the well-known endpoint is not set as active

  Scenario: Re-running discovery after a previously failed attempt
    Given a previous discovery run for context "ctx-abc123" stored no endpoint
    And the cluster now has a Service with label "app.kubernetes.io/name=prometheus" in namespace "monitoring"
    When the operator triggers re-discovery from the settings panel
    Then the discovery pipeline runs again for context "ctx-abc123"
    And a PrometheusEndpoint is created with discovery_source "auto_label"
    And the metrics panel transitions from empty-state to an active dashboard view
