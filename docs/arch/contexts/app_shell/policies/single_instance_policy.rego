# DDD role: Policy
package k8smanager.app_shell.single_instance

# single_instance_policy.rego
#
# Machine-enforceable invariants for app_shell single-instance enforcement
# (ADR-0049, ADR-0042).
#
# input fields:
#   input.lsMultipleInstancesProhibited  — bool: value from Info.plist key
#   input.secondInstanceBehavior         — "activate-existing" | "terminate-new" | "open-new"
#   input.instanceLeaseKey               — string: the lease key acquired on launch

import future.keywords.if

default allow := false

# Instance lease key pattern per ADR-0042.
# 16 lowercase hex characters after the "k8smgr-instance-" prefix.
valid_lease_key_pattern := `^k8smgr-instance-[a-f0-9]{16}$`

# ---------------------------------------------------------------------------
# Happy-path allow
# ---------------------------------------------------------------------------

allow if {
    count(deny_violations) == 0
}

# ---------------------------------------------------------------------------
# Denial rules
# ---------------------------------------------------------------------------

deny_violations[msg] {
    input.lsMultipleInstancesProhibited != true
    msg := "LSMultipleInstancesProhibited must be true in Info.plist; a value of false or absent allows multiple app instances, violating ADR-0042"
}

deny_violations[msg] {
    input.secondInstanceBehavior != "activate-existing"
    msg := sprintf(
        "second-instance behavior %q is not permitted; the only allowed behavior is \"activate-existing\" (NSRunningApplication.activate per ADR-0042)",
        [input.secondInstanceBehavior]
    )
}

deny_violations[msg] {
    not re_match(valid_lease_key_pattern, input.instanceLeaseKey)
    msg := sprintf(
        "instance lease key %q does not match the required pattern ^k8smgr-instance-[a-f0-9]{16}$",
        [input.instanceLeaseKey]
    )
}
