# DDD role: PolicyTest
package port_forwarding.port_forward_policy

import future.keywords.in

# port_forward_policy_test.rego
#
# Unit tests for the bindAddress loopback enforcement added in the
# 2026-05-15 audit fix (tunnel-establish.feature:43-45).

# ---------------------------------------------------------------------------
# Shared base: safe non-privileged open to a non-system namespace
# ---------------------------------------------------------------------------

_base := {
    "sessionAction": "open",
    "localPort": 8080,
    "pod": {
        "name": "nginx-abc",
        "namespace": "default",
        "port": 80,
    },
    "clusterName": "dev",
    "operatorConfirmed": false,
    "bindAddress": "127.0.0.1",
}

# ---------------------------------------------------------------------------
# Loopback addresses → allow
# ---------------------------------------------------------------------------

test_allow_127_0_0_1 {
    allow with input as _base
}

test_allow_ipv6_loopback {
    allow with input as object.union(_base, {"bindAddress": "::1"})
}

test_allow_empty_bind_address_defaults_to_loopback {
    allow with input as object.union(_base, {"bindAddress": ""})
}

test_allow_absent_bind_address_defaults_to_loopback {
    # When bindAddress key is not present at all
    allow with input as {
        "sessionAction": "open",
        "localPort": 8080,
        "pod": {"name": "nginx", "namespace": "default", "port": 80},
        "clusterName": "dev",
        "operatorConfirmed": false,
    }
}

# ---------------------------------------------------------------------------
# Non-loopback addresses → deny
# ---------------------------------------------------------------------------

test_deny_bind_all_interfaces {
    not allow with input as object.union(_base, {"bindAddress": "0.0.0.0"})
}

test_deny_bind_all_fires_msg {
    result := deny_non_loopback_bind_address with input as object.union(
        _base,
        {"bindAddress": "0.0.0.0"}
    )
    count(result) > 0
    some msg in result
    contains(msg, "loopback address")
}

test_deny_non_loopback_specific_ip {
    not allow with input as object.union(_base, {"bindAddress": "192.168.1.10"})
}

test_deny_non_loopback_specific_ip_fires_msg {
    result := deny_non_loopback_bind_address with input as object.union(
        _base,
        {"bindAddress": "192.168.1.10"}
    )
    count(result) > 0
}

test_deny_ipv6_all_interfaces {
    not allow with input as object.union(_base, {"bindAddress": "::"})
}

# ---------------------------------------------------------------------------
# Existing deny rules still work with the new bindAddress field
# ---------------------------------------------------------------------------

test_deny_privileged_port_with_loopback {
    not allow with input as object.union(
        _base,
        {"localPort": 80, "bindAddress": "127.0.0.1"}
    )
}

test_deny_kube_system_without_confirmation_with_loopback {
    not allow with input as object.union(
        _base,
        {
            "pod": {"name": "coredns", "namespace": "kube-system", "port": 53},
            "operatorConfirmed": false,
            "bindAddress": "127.0.0.1",
        }
    )
}

test_allow_kube_system_with_confirmation_and_loopback {
    allow with input as object.union(
        _base,
        {
            "pod": {"name": "coredns", "namespace": "kube-system", "port": 53},
            "operatorConfirmed": true,
            "bindAddress": "127.0.0.1",
        }
    )
}

# ---------------------------------------------------------------------------
# kube-system + non-loopback → deny on both rules
# ---------------------------------------------------------------------------

test_deny_kube_system_and_non_loopback_both_fire {
    confirm_result := deny_kube_system_without_confirmation with input as object.union(
        _base,
        {
            "pod": {"name": "apiserver", "namespace": "kube-system", "port": 6443},
            "operatorConfirmed": false,
            "bindAddress": "0.0.0.0",
        }
    )
    bind_result := deny_non_loopback_bind_address with input as object.union(
        _base,
        {
            "pod": {"name": "apiserver", "namespace": "kube-system", "port": 6443},
            "operatorConfirmed": false,
            "bindAddress": "0.0.0.0",
        }
    )
    count(confirm_result) > 0
    count(bind_result) > 0
}
