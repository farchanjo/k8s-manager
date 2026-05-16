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
# input.templateKey      — string | null: identifier of the curated PromQL
#                          template used to build promQL. Required for any
#                          query issued by `MetricChartViewModel` (ADR-0058)
#                          or by the resource-list mini-bar query batcher
#                          (ADR-0059). Direct ad-hoc queries (operator-typed
#                          PromQL) pass `null`.

default allow := false

# ---------------------------------------------------------------------------
# Curated template-key allowlist (ADR-0058, ADR-0059)
#
# Every PromQL query built from a curated template MUST carry a templateKey
# from this allowlist. Any unknown templateKey is rejected before the HTTP
# request is issued. The allowlist is extended in lockstep with the
# `curated_query_set.cue` schema; drift triggers a deny.
# ---------------------------------------------------------------------------

curated_template_keys := {
    # Node detail drawer chart series (ADR-0058 §PromQL templates per kind / Node)
    "node_drawer_cpu_usage",
    "node_drawer_cpu_requests",
    "node_drawer_cpu_allocatable",
    "node_drawer_cpu_capacity",
    "node_drawer_memory_usage",
    "node_drawer_memory_requests",
    "node_drawer_memory_allocatable",
    "node_drawer_memory_capacity",

    # Pod detail drawer chart series (ADR-0058 §PromQL templates per kind / Pod)
    "pod_drawer_cpu_usage",
    "pod_drawer_cpu_requests",
    "pod_drawer_cpu_limits",
    "pod_drawer_memory_usage",
    "pod_drawer_memory_requests",
    "pod_drawer_memory_limits",

    # Workload detail drawer chart series (Deployment / StatefulSet / DaemonSet)
    "workload_drawer_cpu_aggregate",
    "workload_drawer_memory_aggregate",
    "workload_drawer_replicas_deployment",
    "workload_drawer_replicas_statefulset",
    "workload_drawer_replicas_daemonset",

    # Resource-list row mini-bar batch queries (ADR-0059)
    "node_list_cpu_usage",
    "node_list_cpu_capacity",
    "node_list_memory_usage",
    "node_list_memory_capacity",
    "node_list_disk_usage",
    "node_list_disk_capacity",
    "pod_list_cpu_usage",
    "pod_list_cpu_request",
    "pod_list_memory_usage",
    "pod_list_memory_request",
}

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
# Curated template-key enforcement (ADR-0058, ADR-0059)
#
# When a templateKey is supplied (non-null, non-empty), it MUST be present in
# `curated_template_keys`. Unknown templateKeys indicate either a typo or an
# attempt to bypass the curated template registry. Both are denied.
#
# A null templateKey is permitted: this represents an ad-hoc operator query
# (e.g. typed into the metrics dashboard's PromQL editor), where the label-value
# injection rules above provide the primary defence.
# ---------------------------------------------------------------------------

deny_unknown_template_key[msg] {
    input.templateKey
    input.templateKey != ""
    not curated_template_keys[input.templateKey]
    msg := sprintf(
        "metrics query denied: templateKey %q is not in the curated allowlist; add it to curated_template_keys and to curated_query_set.cue in lockstep",
        [input.templateKey]
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
