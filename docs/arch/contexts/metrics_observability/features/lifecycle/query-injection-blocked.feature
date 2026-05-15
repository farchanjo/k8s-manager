# DDD role: BehaviouralSpecification
# Bounded context: metrics_observability
# References: ADR-0016, ADR-0044
# Rego policy: contexts/metrics_observability/policies/metrics_policy.rego
#
# Refactored 2026-05-15: inlined per-character scenarios converted to a
# Scenario Outline covering all 18 PromQL metacharacters in ADR-0044's
# blocked list.  Original three scenarios replaced by the Outline + Examples
# table; the happy-path and podName scenarios are preserved unchanged.

Feature: PromQL injection blocked when namespace name contains special characters
  As a security-conscious operator
  I want malformed namespace names to be rejected before PromQL template substitution
  So that a namespace name containing "}" cannot break out of a curated query template

  Background:
    Given a Prometheus endpoint is active for "prod-us-east-1"
    And the curated query template is "container_cpu_usage_seconds_total{namespace=\"{namespace}\"}"

  @security @lifecycle
  Scenario Outline: Namespace name containing a PromQL metacharacter is rejected by policy
    Given the resource browser shows namespace <namespace> (containing the character <character>)
    When the operator navigates to the metrics view for a pod in namespace <namespace>
    Then the PrometheusQueryActor evaluates the namespace name against the injection policy (ADR-0044)
    And the policy detects the character <character> which is reserved in PromQL label syntax
    And the query is rejected before template substitution occurs
    And the metrics panel shows "Invalid namespace name — cannot build a safe PromQL query"
    And no HTTP request is sent to the Prometheus /api/v1/query_range endpoint
    And a PromQLInjectionAttemptBlocked audit entry is written with the offending value digest

    Examples:
      | character | namespace                |
      | "{"       | 'ns-evil{'               |
      | "}"       | 'ns-evil}'               |
      | "'"       | "ns-evil'"               |
      | '"'       | 'ns-evil"'               |
      | ";"       | 'ns-evil;'               |
      | "\|"      | 'ns-evil\|'              |
      | "("       | 'ns-evil('               |
      | ")"       | 'ns-evil)'               |
      | "["       | 'ns-evil['               |
      | "]"       | 'ns-evil]'               |
      | "\\"      | 'ns-evil\\'              |
      | "<"       | 'ns-evil<'               |
      | ">"       | 'ns-evil>'               |
      | "*"       | 'ns-evil*'               |
      | "="       | 'ns-evil='               |
      | "@"       | 'ns-evil@'               |
      | "space"   | 'ns evil'                |
      | "`"       | 'ns-evil`'               |

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
