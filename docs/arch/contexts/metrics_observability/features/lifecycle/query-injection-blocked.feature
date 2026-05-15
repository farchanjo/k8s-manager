# DDD role: BehaviouralSpecification
# Bounded context: metrics_observability
# References: ADR-0016

Feature: PromQL injection blocked when namespace name contains special characters
  As a security-conscious operator
  I want malformed namespace names to be rejected before PromQL template substitution
  So that a namespace name containing "}" cannot break out of a curated query template

  Background:
    Given a Prometheus endpoint is active for "prod-us-east-1"
    And the curated query template is "container_cpu_usage_seconds_total{namespace=\"{namespace}\"}"

  @security @lifecycle
  Scenario: Namespace name containing "}" is rejected by policy before substitution
    Given the resource browser shows namespace 'evil}' (containing a closing brace)
    When the operator navigates to the metrics view for a pod in namespace 'evil}'
    Then the PrometheusQueryActor evaluates the namespace name against the injection policy
    And the policy detects the character "}" which is reserved in PromQL label syntax
    And the query is rejected before template substitution occurs
    And the metrics panel shows "Invalid namespace name — cannot build a safe PromQL query"
    And no HTTP request is sent to the Prometheus /api/v1/query_range endpoint

  @security @lifecycle
  Scenario: Namespace name containing curly brace opener is also rejected
    Given a namespace is named 'bad{ns'
    When the operator navigates to its metrics view
    Then the injection policy also rejects "{" in namespace names
    And no query is dispatched

  @happy @lifecycle
  Scenario: Well-formed namespace name passes policy and query succeeds
    Given the resource browser shows namespace "production" (contains only alphanumerics and hyphens)
    When the operator navigates to the metrics view
    Then the policy accepts "production" as a safe namespace name
    And the template substitution produces a valid PromQL expression
    And the HTTP query succeeds and data is displayed in the dashboard

  @security @lifecycle
  Scenario: PodName parameter with PromQL metacharacter is rejected
    Given a pod is named 'pod"evil' (contains a double-quote)
    When the curated query substitutes {podName} with 'pod"evil'
    Then the injection policy detects the double-quote in the pod name
    And the query is rejected with reason "unsafe pod name for PromQL substitution"
    And no HTTP request is sent
