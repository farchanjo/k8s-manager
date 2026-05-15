# DDD role: Policy
package port_forwarding.port_forward_policy

# port_forward_policy.rego
#
# Governs which port-forward tunnels may be opened. Every tunnel open
# and close event is written to the audit trail.
#
# input.localPort          — int: the local TCP port the operator requested
# input.pod.name           — string: target Pod name
# input.pod.namespace      — string: target Pod namespace
# input.pod.port           — int: target container port
# input.clusterName        — string: cluster name
# input.operatorConfirmed  — bool: operator acknowledged a confirmation prompt
# input.sessionAction      — "open" or "close"
# input.bindAddress        — string: local address the tunnel binds to.
#                            Omitting this field is treated as "127.0.0.1"
#                            (loopback-only, safe default). Only "127.0.0.1",
#                            "::1", and "" (absent — defaults to loopback) are
#                            permitted; any other address (e.g. "0.0.0.0") is
#                            denied because it exposes the tunnel on all
#                            network interfaces.

default allow := false

# ---------------------------------------------------------------------------
# Helper — bind address is safe (loopback only)
# Absent field ("") is treated as "127.0.0.1" per the input schema contract.
# ---------------------------------------------------------------------------

bind_address_is_loopback {
    input.bindAddress == "127.0.0.1"
}

bind_address_is_loopback {
    input.bindAddress == "::1"
}

bind_address_is_loopback {
    input.bindAddress == ""
}

# bindAddress absent from input → default to safe loopback
bind_address_is_loopback {
    not input.bindAddress
}

# ---------------------------------------------------------------------------
# Happy-path allow: non-privileged local port, non-kube-system target,
#                   loopback bind address.
# ---------------------------------------------------------------------------

allow {
    input.sessionAction == "open"
    input.localPort >= 1024
    input.pod.namespace != "kube-system"
    bind_address_is_loopback
}

# ---------------------------------------------------------------------------
# Happy-path allow: kube-system target with explicit confirmation,
#                   loopback bind address.
# ---------------------------------------------------------------------------

allow {
    input.sessionAction == "open"
    input.localPort >= 1024
    input.pod.namespace == "kube-system"
    input.operatorConfirmed == true
    bind_address_is_loopback
}

# ---------------------------------------------------------------------------
# Deny rules
# ---------------------------------------------------------------------------

deny_privileged_local_port[msg] {
    input.sessionAction == "open"
    input.localPort < 1024
    msg := sprintf(
        "port-forward denied: local port %d is a privileged port (< 1024); use a port >= 1024",
        [input.localPort]
    )
}

deny_kube_system_without_confirmation[msg] {
    input.sessionAction == "open"
    input.pod.namespace == "kube-system"
    input.operatorConfirmed == false
    msg := sprintf(
        "port-forward denied: target pod %q is in kube-system namespace; explicit operator confirmation is required",
        [input.pod.name]
    )
}

deny_non_loopback_bind_address[msg] {
    input.sessionAction == "open"
    not bind_address_is_loopback
    msg := sprintf(
        "port-forward denied: bindAddress %q is not a loopback address; only 127.0.0.1 and ::1 are permitted to prevent tunnel exposure on all network interfaces (tunnel-establish.feature:43-45)",
        [input.bindAddress]
    )
}

# ---------------------------------------------------------------------------
# Audit obligation
# ---------------------------------------------------------------------------

audit_required := true

# ---------------------------------------------------------------------------
# Negative test cases
#
# test_deny_privileged_port_80:
#   input = {
#     "sessionAction": "open",
#     "localPort": 80,
#     "pod": {"name": "nginx", "namespace": "default", "port": 8080},
#     "clusterName": "dev",
#     "operatorConfirmed": false
#   }
#   expect: allow == false
#   expect: deny_privileged_local_port contains "privileged port"
#
# test_deny_kube_system_no_confirm:
#   input = {
#     "sessionAction": "open",
#     "localPort": 8080,
#     "pod": {"name": "coredns-abc", "namespace": "kube-system", "port": 53},
#     "clusterName": "prod",
#     "operatorConfirmed": false
#   }
#   expect: allow == false
#   expect: deny_kube_system_without_confirmation contains "kube-system namespace"
#
# test_deny_privileged_port_in_kube_system:
#   input = {
#     "sessionAction": "open",
#     "localPort": 443,
#     "pod": {"name": "apiserver", "namespace": "kube-system", "port": 6443},
#     "clusterName": "prod",
#     "operatorConfirmed": true
#   }
#   expect: allow == false
#   expect: deny_privileged_local_port contains "privileged port"
# ---------------------------------------------------------------------------
