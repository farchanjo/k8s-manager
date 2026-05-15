# DDD role: Policy
package terminal_session.terminal_policy

# terminal_policy.rego
#
# Governs which Pod exec sessions may be opened and under what conditions
# a privileged Pod may be targeted. Every session open and close event
# is written to the audit trail regardless of the allow/deny outcome.
#
# input.pod.hostNetwork     — bool: the Pod has hostNetwork: true
# input.pod.hostPID         — bool: the Pod has hostPID: true
# input.pod.privileged      — bool: at least one container runs with
#                             securityContext.privileged: true
# input.pod.name            — string: Pod name
# input.pod.namespace       — string: Pod namespace
# input.pod.createdAt       — RFC3339: Pod creation timestamp
# input.clusterName         — string: the cluster name as typed by the operator
# input.clusterNameConfirmed — string: the cluster name the operator typed
#                              into the confirmation prompt (empty if not shown)
# input.isDebugPod          — bool: Pod was created by K8sManager's debug
#                             session launcher within the current session
# input.debugPodCreatedAt   — RFC3339: timestamp of debug Pod creation
#                             (relevant only when isDebugPod is true)
# input.requestedAt         — RFC3339: timestamp of this policy evaluation
# input.sessionAction       — "open" or "close"
#
# The grace TTL for freshly-created debug Pods is 60 seconds.
debug_pod_grace_ttl_seconds := 60

default allow := false

# ---------------------------------------------------------------------------
# Happy-path: non-privileged Pod
# Allow exec into any Pod that does not have hostNetwork, hostPID, or
# privileged containers. No confirmation required.
# ---------------------------------------------------------------------------

allow {
    input.sessionAction == "open"
    not input.pod.hostNetwork
    not input.pod.hostPID
    not input.pod.privileged
}

# ---------------------------------------------------------------------------
# Happy-path: privileged Pod with operator cluster-name confirmation
# and freshly-created debug Pod within the grace TTL
# ---------------------------------------------------------------------------

allow {
    input.sessionAction == "open"
    is_privileged_pod
    input.clusterNameConfirmed == input.clusterName
    input.isDebugPod == true
    within_grace_ttl
}

# A Pod is privileged if any of the three flags are set.
is_privileged_pod {
    input.pod.hostNetwork == true
}

is_privileged_pod {
    input.pod.hostPID == true
}

is_privileged_pod {
    input.pod.privileged == true
}

# The debug Pod was created within the last 60 seconds relative to now.
within_grace_ttl {
    # Both timestamps are RFC3339; time.parse_ns returns nanoseconds.
    created := time.parse_ns("2006-01-02T15:04:05Z07:00", input.debugPodCreatedAt)
    requested := time.parse_ns("2006-01-02T15:04:05Z07:00", input.requestedAt)
    (requested - created) <= (debug_pod_grace_ttl_seconds * 1000000000)
}

# ---------------------------------------------------------------------------
# Deny rules
# ---------------------------------------------------------------------------

deny_privileged_without_confirmation[msg] {
    input.sessionAction == "open"
    is_privileged_pod
    input.clusterNameConfirmed != input.clusterName
    msg := sprintf(
        "exec session denied: pod %q in namespace %q has privileged security context (hostNetwork=%v hostPID=%v privileged=%v); operator must type the cluster name %q to proceed",
        [input.pod.name, input.pod.namespace,
         input.pod.hostNetwork, input.pod.hostPID, input.pod.privileged,
         input.clusterName]
    )
}

deny_privileged_pod_not_debug[msg] {
    input.sessionAction == "open"
    is_privileged_pod
    input.clusterNameConfirmed == input.clusterName
    input.isDebugPod == false
    msg := sprintf(
        "exec session denied: pod %q is privileged but was not created by K8sManager's debug session launcher; operator confirmation alone is insufficient for persistent privileged Pods",
        [input.pod.name]
    )
}

deny_privileged_debug_pod_expired[msg] {
    input.sessionAction == "open"
    is_privileged_pod
    input.clusterNameConfirmed == input.clusterName
    input.isDebugPod == true
    not within_grace_ttl
    msg := sprintf(
        "exec session denied: debug pod %q exceeded the %d-second grace TTL; the pod must be recreated to open an exec session",
        [input.pod.name, debug_pod_grace_ttl_seconds]
    )
}

# ---------------------------------------------------------------------------
# Audit obligation (non-negotiable)
# Every open and close event is recorded. The audit obligation is documented
# here as a policy rule so that conformance tests can verify it is checked.
# The application layer is responsible for the actual SQLite write.
#
# audit_required is always true; it acts as a machine-readable assertion
# that the audit write must precede any session state change.
# ---------------------------------------------------------------------------

audit_required := true

# ---------------------------------------------------------------------------
# Negative test cases
#
# test_deny_host_network_pod_no_confirmation:
#   input = {
#     "sessionAction": "open",
#     "pod": {"hostNetwork": true, "hostPID": false, "privileged": false,
#             "name": "net-pod", "namespace": "default", "createdAt": "2026-05-15T10:00:00Z"},
#     "clusterName": "prod", "clusterNameConfirmed": "",
#     "isDebugPod": false, "debugPodCreatedAt": "",
#     "requestedAt": "2026-05-15T10:00:01Z"
#   }
#   expect: allow == false
#   expect: deny_privileged_without_confirmation contains "must type the cluster name"
#
# test_deny_privileged_non_debug_with_confirmation:
#   input = {
#     "sessionAction": "open",
#     "pod": {"hostNetwork": false, "hostPID": false, "privileged": true,
#             "name": "priv-pod", "namespace": "kube-system", "createdAt": "2026-05-15T09:00:00Z"},
#     "clusterName": "prod", "clusterNameConfirmed": "prod",
#     "isDebugPod": false, "debugPodCreatedAt": "",
#     "requestedAt": "2026-05-15T10:00:01Z"
#   }
#   expect: allow == false
#   expect: deny_privileged_pod_not_debug contains "was not created by K8sManager"
#
# test_deny_expired_debug_pod:
#   input = {
#     "sessionAction": "open",
#     "pod": {"hostNetwork": true, "hostPID": false, "privileged": false,
#             "name": "debug-pod", "namespace": "default", "createdAt": "2026-05-15T09:00:00Z"},
#     "clusterName": "prod", "clusterNameConfirmed": "prod",
#     "isDebugPod": true, "debugPodCreatedAt": "2026-05-15T09:00:00Z",
#     "requestedAt": "2026-05-15T10:00:01Z"
#   }
#   expect: allow == false
#   expect: deny_privileged_debug_pod_expired contains "exceeded the 60-second grace TTL"
# ---------------------------------------------------------------------------
