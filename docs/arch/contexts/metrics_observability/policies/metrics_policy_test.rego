# DDD role: PolicyTest
package metrics_observability.metrics_policy

import future.keywords.in

# metrics_policy_test.rego
#
# Unit tests for metrics_policy.rego — specifically validates the ADR-0044
# allowlist rule ^[a-zA-Z0-9._-]{1,63}$ replacing the previous deny-list.

import future.keywords.every
import future.keywords.in

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

_proxy_url := "https://k8s.example.com/api/v1/namespaces/monitoring/services/prometheus:9090/proxy/api/v1/query"

_valid_base := {
    "endpointURL": _proxy_url,
    "promQL": "up",
    "labelValues": {},
    "queryTimeoutSecs": 10,
    "clusterName": "prod",
}

# ---------------------------------------------------------------------------
# label_value_safe — allowlist positive cases
# ---------------------------------------------------------------------------

test_allow_alphanumeric_label_value {
    label_value_safe("default")
}

test_allow_label_value_with_dot {
    label_value_safe("kube-system.v2")
}

test_allow_label_value_with_underscore {
    label_value_safe("my_namespace")
}

test_allow_label_value_with_hyphen {
    label_value_safe("my-namespace")
}

test_allow_label_value_mixed_allowed_chars {
    label_value_safe("app-v1.2_3")
}

test_allow_label_value_single_char {
    label_value_safe("x")
}

test_allow_label_value_63_chars {
    # exactly 63 characters — at the boundary
    label_value_safe("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
}

# ---------------------------------------------------------------------------
# label_value_safe — allowlist negative cases (ADR-0044 violations)
# ---------------------------------------------------------------------------

test_deny_label_value_with_lt {
    not label_value_safe("<injection>")
}

test_deny_label_value_with_gt {
    not label_value_safe("value>bad")
}

test_deny_label_value_with_asterisk {
    not label_value_safe("kube*")
}

test_deny_label_value_with_equals {
    not label_value_safe("k=v")
}

test_deny_label_value_with_at {
    not label_value_safe("user@host")
}

test_deny_label_value_with_space {
    not label_value_safe("has space")
}

test_deny_label_value_empty {
    # empty string has length 0 — fails {1,63} quantifier
    not label_value_safe("")
}

test_deny_label_value_64_chars {
    # 64 characters — one over the maximum
    not label_value_safe("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
}

test_deny_label_value_with_curly_brace {
    not label_value_safe("{namespace=default}")
}

test_deny_label_value_with_quote {
    not label_value_safe(`val"injected`)
}

test_deny_label_value_with_semicolon {
    not label_value_safe("val;evil")
}

test_deny_label_value_with_pipe {
    not label_value_safe("val|other")
}

test_deny_label_value_with_comma {
    not label_value_safe("a,b")
}

# ---------------------------------------------------------------------------
# deny_unsafe_label_value — full policy deny set
# ---------------------------------------------------------------------------

test_deny_fires_for_lt_in_label {
    result := deny_unsafe_label_value with input as object.union(
        _valid_base,
        {"labelValues": {"ns": "<kube-system>"}}
    )
    count(result) > 0
    some msg in result
    contains(msg, "ADR-0044")
}

test_deny_fires_for_space_in_label {
    result := deny_unsafe_label_value with input as object.union(
        _valid_base,
        {"labelValues": {"app": "my app"}}
    )
    count(result) > 0
}

test_deny_fires_for_empty_label_value {
    result := deny_unsafe_label_value with input as object.union(
        _valid_base,
        {"labelValues": {"env": ""}}
    )
    count(result) > 0
}

test_deny_fires_for_64_char_label_value {
    result := deny_unsafe_label_value with input as object.union(
        _valid_base,
        {"labelValues": {"env": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}
    )
    count(result) > 0
}

# ---------------------------------------------------------------------------
# allow — safe label values must not trigger deny
# ---------------------------------------------------------------------------

test_allow_safe_label_value_does_not_fire_deny {
    result := deny_unsafe_label_value with input as object.union(
        _valid_base,
        {"labelValues": {"namespace": "kube-system"}}
    )
    count(result) == 0
}

test_allow_full_policy_with_valid_labels {
    allow with input as object.union(
        _valid_base,
        {"labelValues": {"namespace": "default", "app": "my-app_v1.0"}}
    )
}
