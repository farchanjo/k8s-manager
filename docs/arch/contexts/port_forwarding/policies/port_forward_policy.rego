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

default allow := false

# ---------------------------------------------------------------------------
# Happy-path allow: non-privileged local port, non-kube-system target
# ---------------------------------------------------------------------------

allow {
    input.sessionAction == "open"
    input.localPort >= 1024
    input.pod.namespace != "kube-system"
}

# ---------------------------------------------------------------------------
# Happy-path allow: kube-system target with explicit confirmation
# ---------------------------------------------------------------------------

allow {
    input.sessionAction == "open"
    input.localPort >= 1024
    input.pod.namespace == "kube-system"
    input.operatorConfirmed == true
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
