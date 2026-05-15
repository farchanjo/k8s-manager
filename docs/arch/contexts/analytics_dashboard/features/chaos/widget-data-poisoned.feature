# DDD role: ChaosScenario
# Bounded context: analytics_dashboard
# References: ADR-0024, ADR-0010, ADR-0016
# Rego policy: contexts/_shared/policies/secret_redaction.rego

Feature: Widget data poisoned — adversarial metric label values from Prometheus
  As a security-conscious operator
  I want widgets to render safely without crashing when Prometheus returns
  adversarial label values that could contain secrets or injection payloads
  So that a compromised scrape target cannot disrupt the dashboard or expose credentials

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Prometheus endpoint has been discovered at "http://prometheus-operated.monitoring.svc:9090"
    And the ClusterOverview dashboard is open with the "top-namespaces-cpu" TopList widget active

  @chaos @security
  Scenario: Prometheus returns metric labels containing credential-pattern strings
    Given the Prometheus endpoint returns a vector result where one series has the label
          namespace="Bearer eyJhbGciOiJSUzI1NiJ9.secret-token-here"
    When the PrometheusQueryActor processes the result
    Then the secret_redaction policy evaluates each label value against the bearer-token pattern
    And the label value matching "Bearer [A-Za-z0-9._-]{20,}" is replaced with "Bearer [REDACTED]"
    And the widget renders the row with the redacted label text "[REDACTED]"
    And no raw credential value appears in the widget cell, tooltip, or accessibility label
    And the redaction is recorded in the diagnostics log at level INFO

  @chaos @security
  Scenario: Prometheus returns adversarial label with PromQL metacharacters — widget renders safely
    Given the Prometheus endpoint returns a series with label value
          namespace='evil}; drop table metrics; --'
    When the PrometheusQueryActor receives the poisoned series
    Then the widget renders the namespace label as a literal display string without evaluation
    And no secondary PromQL query is constructed using the raw label value
    And the namespace cell in the TopList widget displays the verbatim text (truncated if > 64 chars)
    And no JavaScript evaluation, SQL execution, or shell expansion of the label value occurs
    And the widget does not crash or show an error state — it renders the row as normal data
