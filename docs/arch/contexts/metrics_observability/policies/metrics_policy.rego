# DDD role: Policy
package metrics_observability.metrics_policy

import future.keywords.every
import future.keywords.in

# metrics_policy.rego
#
# Governs Prometheus query execution. Mitigates PromQL injection via
# label-value regex validation, restricts endpoint access to the
# kube-apiserver proxy path, and enforces a 30-second query timeout.
#
# input.endpointURL      — string: the full Prometheus query URL
# input.promQL           — string: the PromQL expression
# input.labelValues      — {string: string}: map of label name → value
#                          extracted from the query (for injection checks)
# input.queryTimeoutSecs — int: requested query timeout in seconds
# input.clusterName      — string: cluster context name

default allow := false

# ---------------------------------------------------------------------------
# Allowed endpoint patterns
# Prometheus must be reached via the kube-apiserver proxy path only.
# Direct in-cluster IPs (e.g. 10.x.x.x:9090) are not permitted.
# ---------------------------------------------------------------------------

is_via_apiserver_proxy(url) {
    contains(url, "/api/v1/namespaces/")
    contains(url, "/services/")
    contains(url, "/proxy/")
}

# ---------------------------------------------------------------------------
# PromQL injection mitigations
# Label values that come from operator input must conform to an explicit
# allowlist (ADR-0044 line 44): ^[a-zA-Z0-9._-]{1,63}$
# Only alphanumeric characters, dots, underscores, and hyphens are permitted.
# Length is capped at 63 characters (Kubernetes label-value limit).
# Any character outside this set — including spaces, @, #, $, ^, ~, +, =,
# ?, <, >, comma, backtick — is rejected.
# ---------------------------------------------------------------------------

label_value_safe(val) {
    regex.match(`^[a-zA-Z0-9._\-]{1,63}$`, val)
}

all_label_values_safe {
    every _, val in input.labelValues {
        label_value_safe(val)
    }
}

# ---------------------------------------------------------------------------
# Happy-path allow
# ---------------------------------------------------------------------------

allow {
    is_via_apiserver_proxy(input.endpointURL)
    all_label_values_safe
    input.queryTimeoutSecs <= 30
}

# ---------------------------------------------------------------------------
# Deny rules
# ---------------------------------------------------------------------------

deny_direct_cluster_ip_endpoint[msg] {
    not is_via_apiserver_proxy(input.endpointURL)
    msg := sprintf(
        "metrics query denied: endpoint %q is not routed via the kube-apiserver proxy; direct in-cluster Prometheus IPs are not permitted",
        [input.endpointURL]
    )
}

deny_unsafe_label_value[msg] {
    some name, val in input.labelValues
    not label_value_safe(val)
    msg := sprintf(
        "metrics query denied: label %q has value %q that does not match the allowed pattern ^[a-zA-Z0-9._-]{1,63}$; only alphanumeric characters, dots, underscores, and hyphens (max 63 chars) are permitted (ADR-0044)",
        [name, val]
    )
}

deny_query_timeout_exceeded[msg] {
    input.queryTimeoutSecs > 30
    msg := sprintf(
        "metrics query denied: requested timeout %d seconds exceeds the maximum permitted timeout of 30 seconds",
        [input.queryTimeoutSecs]
    )
}

# ---------------------------------------------------------------------------
# Negative test cases
#
# test_deny_direct_prometheus_ip:
#   input = {
#     "endpointURL": "http://10.96.0.10:9090/api/v1/query",
#     "promQL": "up",
#     "labelValues": {},
#     "queryTimeoutSecs": 10,
#     "clusterName": "prod"
#   }
#   expect: allow == false
#   expect: deny_direct_cluster_ip_endpoint contains "not routed via the kube-apiserver proxy"
#
# test_deny_promql_injection_in_label_value:
#   input = {
#     "endpointURL": "https://k8s.example.com/api/v1/namespaces/monitoring/services/prometheus:9090/proxy/api/v1/query",
#     "promQL": "http_requests_total{namespace=\"default\"}",
#     "labelValues": {"namespace": "default\"}[evil_metric{foo=\"bar"}"},
#     "queryTimeoutSecs": 10,
#     "clusterName": "prod"
#   }
#   expect: allow == false
#   expect: deny_unsafe_label_value contains "could inject PromQL"
#
# test_deny_query_timeout_too_long:
#   input = {
#     "endpointURL": "https://k8s.example.com/api/v1/namespaces/monitoring/services/prometheus:9090/proxy/api/v1/query",
#     "promQL": "up",
#     "labelValues": {},
#     "queryTimeoutSecs": 60,
#     "clusterName": "prod"
#   }
#   expect: allow == false
#   expect: deny_query_timeout_exceeded contains "exceeds the maximum permitted timeout"
# ---------------------------------------------------------------------------
