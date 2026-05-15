# DDD role: PolicyTest
package cluster_connectivity.subprocess_exec_allowlist

import future.keywords.in

# subprocess_exec_allowlist_test.rego
#
# Unit tests for the first-seen / operator-approval invariant coupling.
# Verifies that allow and deny_missing_operator_approval_for_new_command
# are no longer contradictory: a first-seen unapproved binary always
# produces allow == false, regardless of directory.

# ---------------------------------------------------------------------------
# Shared base: safe regular file in an approved Homebrew directory
# ---------------------------------------------------------------------------

_base_homebrew := {
    "resolvedPath": "/opt/homebrew/bin/aws-iam-authenticator",
    "isRegularFile": true,
    "isWorldWritable": false,
    "symlinkTarget": "",
    "symlinkTargetWorld": false,
    "kubeconfig": "/Users/operator/.kube/config",
    "contextName": "prod",
    "operatorApproved": false,
    "previouslySeen": false,
}

# ---------------------------------------------------------------------------
# Fix 2 core: first-seen without approval → deny
# ---------------------------------------------------------------------------

test_deny_first_seen_unapproved {
    not allow with input as _base_homebrew
}

test_deny_msg_fires_for_first_seen_unapproved {
    result := deny_missing_operator_approval_for_new_command with input as _base_homebrew
    count(result) > 0
    some msg in result
    contains(msg, "UX prompt must be shown")
}

# ---------------------------------------------------------------------------
# Fix 2 core: previously-seen → allow
# ---------------------------------------------------------------------------

test_allow_previously_seen {
    allow with input as object.union(_base_homebrew, {"previouslySeen": true})
}

test_no_deny_msg_for_previously_seen {
    result := deny_missing_operator_approval_for_new_command with input as object.union(
        _base_homebrew,
        {"previouslySeen": true}
    )
    count(result) == 0
}

# ---------------------------------------------------------------------------
# Fix 2 core: operator-approved (even first-seen) → allow
# ---------------------------------------------------------------------------

test_allow_operator_approved {
    allow with input as object.union(_base_homebrew, {"operatorApproved": true})
}

test_no_deny_msg_for_operator_approved {
    result := deny_missing_operator_approval_for_new_command with input as object.union(
        _base_homebrew,
        {"operatorApproved": true}
    )
    count(result) == 0
}

# ---------------------------------------------------------------------------
# Both previouslySeen and operatorApproved → allow
# ---------------------------------------------------------------------------

test_allow_both_seen_and_approved {
    allow with input as object.union(
        _base_homebrew,
        {"previouslySeen": true, "operatorApproved": true}
    )
}

# ---------------------------------------------------------------------------
# Symlink path: previously-seen → allow; first-seen → deny
# ---------------------------------------------------------------------------

_base_symlink := {
    "resolvedPath": "/usr/local/bin/kubectl",
    "isRegularFile": false,
    "isWorldWritable": false,
    "symlinkTarget": "/opt/homebrew/Cellar/kubernetes-cli/1.30.0/bin/kubectl",
    "symlinkTargetWorld": false,
    "kubeconfig": "/Users/operator/.kube/config",
    "contextName": "staging",
    "operatorApproved": false,
    "previouslySeen": false,
}

test_deny_first_seen_symlink_unapproved {
    not allow with input as _base_symlink
}

test_allow_previously_seen_symlink {
    allow with input as object.union(_base_symlink, {"previouslySeen": true})
}

test_allow_operator_approved_symlink {
    allow with input as object.union(_base_symlink, {"operatorApproved": true})
}

# ---------------------------------------------------------------------------
# Unapproved directory always denies (regardless of approval flags)
# ---------------------------------------------------------------------------

test_deny_unapproved_directory {
    not allow with input as {
        "resolvedPath": "/tmp/evil-plugin",
        "isRegularFile": true,
        "isWorldWritable": false,
        "symlinkTarget": "",
        "symlinkTargetWorld": false,
        "kubeconfig": "/Users/operator/.kube/config",
        "contextName": "prod",
        "operatorApproved": false,
        "previouslySeen": true,
    }
}

# ---------------------------------------------------------------------------
# World-writable binary always denies
# ---------------------------------------------------------------------------

test_deny_world_writable_even_if_seen {
    not allow with input as object.union(
        _base_homebrew,
        {"isWorldWritable": true, "previouslySeen": true}
    )
}
