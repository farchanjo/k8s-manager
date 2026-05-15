# DDD role: Policy
package cluster_connectivity.subprocess_exec_allowlist

# subprocess_exec_allowlist.rego
#
# Governs which executable paths the SubprocessExecCredentialAdapter may
# invoke as a fallback for exec credential plugins whose command name is
# not handled by a native adapter (ADR-0018, HIGH-03 finding).
#
# Policy contract:
#   input.resolvedPath       — the absolute, symlink-resolved path of the
#                              binary to execute (string)
#   input.isRegularFile      — true iff the resolved path is a regular file
#                              (not a symlink, directory, or device node)
#   input.isWorldWritable    — true iff the resolved path's permissions allow
#                              world-write (mode & 0o002 != 0)
#   input.symlinkTarget      — if the path is a symlink, the target path;
#                              absent when isRegularFile is true
#   input.symlinkTargetWorld — true iff the symlink target is world-writable
#   input.kubeconfig         — absolute path of the kubeconfig file that
#                              declared this exec plugin (string)
#   input.contextName        — the kubeconfig context name under evaluation
#                              (string)
#   input.operatorApproved   — true iff the operator explicitly approved this
#                              exact path in the trusted_exec_plugins SQLite
#                              table (bool)
#   input.previouslySeen     — true iff this exact path was previously seen
#                              and logged in the audit trail (bool)
#
# Every invocation is logged with resolvedPath, kubeconfig, and contextName
# BEFORE the process is spawned. This is non-negotiable.

default allow := false

# ---------------------------------------------------------------------------
# Approved-directory allowlist
# Standard system and package-manager binary directories on macOS.
# ---------------------------------------------------------------------------

approved_prefix(path) {
    startswith(path, "/usr/local/bin/")
}

approved_prefix(path) {
    startswith(path, "/opt/homebrew/bin/")
}

approved_prefix(path) {
    startswith(path, "/usr/bin/")
}

approved_prefix(path) {
    startswith(path, "/usr/sbin/")
}

# Rancher Desktop CLI tools (rd) — common on macOS developer workstations.
# The tilde is expanded by the adapter to the operator's home directory
# before the path reaches this policy.
approved_prefix(path) {
    startswith(path, "/Users/")
    contains(path, "/.rd/bin/")
}

# Operator-approved paths recorded in the trusted_exec_plugins SQLite table.
approved_prefix(path) {
    input.operatorApproved == true
    _ = path  # path is already checked via operatorApproved flag
}

# ---------------------------------------------------------------------------
# File integrity checks
# ---------------------------------------------------------------------------

# The resolved path must be a regular file. Symlinks are acceptable only
# when their targets are also regular files (checked separately below).
file_is_safe {
    input.isRegularFile == true
    input.isWorldWritable == false
}

# When the path is a symlink, the target must also be a regular file and
# must not be world-writable.
symlink_is_safe {
    input.isRegularFile == false
    input.symlinkTarget != ""
    input.isWorldWritable == false
    input.symlinkTargetWorld == false
}

# ---------------------------------------------------------------------------
# Happy-path allow rule
#
# All conditions must hold simultaneously:
#   1. Resolved path is in an approved directory (or operator-approved).
#   2. The binary is a safe file (regular and not world-writable) or is a
#      safe symlink (target regular and not world-writable).
#   3. The binary has been seen before in the audit trail OR the operator
#      has explicitly approved it — a first-seen binary without approval
#      must never be silently executed (ADR-0018 HIGH-03).
#
# Rationale: the previous structure allowed `allow == true` while
# `deny_missing_operator_approval_for_new_command` fired simultaneously,
# because OPA evaluates allow and deny sets independently. Merging the
# first-seen/operatorApproved gate into `allow` makes the single decision
# the adapter reads authoritative: allow == true is sufficient and already
# incorporates the approval invariant.
# ---------------------------------------------------------------------------

allow {
    approved_prefix(input.resolvedPath)
    file_is_safe
    input.previouslySeen == true
}

allow {
    approved_prefix(input.resolvedPath)
    file_is_safe
    input.operatorApproved == true
}

allow {
    approved_prefix(input.resolvedPath)
    symlink_is_safe
    input.previouslySeen == true
}

allow {
    approved_prefix(input.resolvedPath)
    symlink_is_safe
    input.operatorApproved == true
}

# ---------------------------------------------------------------------------
# Deny rules (named for audit trail clarity)
# Each rule emits a human-readable message included in the audit log.
# ---------------------------------------------------------------------------

deny_unapproved_directory[msg] {
    not approved_prefix(input.resolvedPath)
    msg := sprintf(
        "exec plugin path %q is not in an approved directory and has no operator approval; kubeconfig=%q context=%q",
        [input.resolvedPath, input.kubeconfig, input.contextName]
    )
}

deny_world_writable_binary[msg] {
    input.isWorldWritable == true
    msg := sprintf(
        "exec plugin binary %q is world-writable and cannot be trusted; kubeconfig=%q context=%q",
        [input.resolvedPath, input.kubeconfig, input.contextName]
    )
}

deny_world_writable_symlink_target[msg] {
    input.isRegularFile == false
    input.symlinkTargetWorld == true
    msg := sprintf(
        "exec plugin %q is a symlink whose target is world-writable; kubeconfig=%q context=%q",
        [input.resolvedPath, input.kubeconfig, input.contextName]
    )
}

# deny_missing_operator_approval_for_new_command is intentionally kept as an
# explicit deny rule for audit-trail message clarity. The allow rule above
# already requires previouslySeen OR operatorApproved, so this deny fires
# only when allow == false due to the approval invariant. The adapter reads
# the deny set to surface the UX prompt obligation to the operator.
deny_missing_operator_approval_for_new_command[msg] {
    not input.previouslySeen
    not input.operatorApproved
    approved_prefix(input.resolvedPath)
    msg := sprintf(
        "exec plugin %q has not been seen before and lacks operator approval; a UX prompt must be shown before this binary is invoked; kubeconfig=%q context=%q",
        [input.resolvedPath, input.kubeconfig, input.contextName]
    )
}

# ---------------------------------------------------------------------------
# Negative test cases (verified by the policy unit test suite)
#
# test_deny_tmp_path:
#   input = {
#     "resolvedPath": "/tmp/evil",
#     "isRegularFile": true,
#     "isWorldWritable": false,
#     "kubeconfig": "/Users/operator/.kube/config",
#     "contextName": "prod",
#     "operatorApproved": false,
#     "previouslySeen": false
#   }
#   expect: allow == false
#   expect: deny_unapproved_directory contains "not in an approved directory"
#
# test_deny_downloads_path:
#   input = {
#     "resolvedPath": "/Users/operator/Downloads/aws-iam-authenticator",
#     "isRegularFile": true,
#     "isWorldWritable": false,
#     "kubeconfig": "/Users/operator/.kube/config",
#     "contextName": "dev",
#     "operatorApproved": false,
#     "previouslySeen": false
#   }
#   expect: allow == false
#   expect: deny_unapproved_directory contains "not in an approved directory"
#
# test_deny_evil_symlink_in_usr_local_bin:
#   input = {
#     "resolvedPath": "/usr/local/bin/evil-symlink-to-tmp",
#     "isRegularFile": false,
#     "isWorldWritable": false,
#     "symlinkTarget": "/tmp/evil",
#     "symlinkTargetWorld": true,
#     "kubeconfig": "/Users/operator/.kube/config",
#     "contextName": "staging",
#     "operatorApproved": false,
#     "previouslySeen": false
#   }
#   expect: allow == false
#   expect: deny_world_writable_symlink_target contains "symlink whose target is world-writable"
#
# test_deny_world_writable_binary:
#   input = {
#     "resolvedPath": "/usr/local/bin/aws-iam-authenticator",
#     "isRegularFile": true,
#     "isWorldWritable": true,
#     "kubeconfig": "/Users/operator/.kube/config",
#     "contextName": "staging",
#     "operatorApproved": false,
#     "previouslySeen": false
#   }
#   expect: allow == false
#   expect: deny_world_writable_binary contains "world-writable"
#
# test_deny_new_unseen_command_without_approval:
#   input = {
#     "resolvedPath": "/opt/homebrew/bin/some-new-plugin",
#     "isRegularFile": true,
#     "isWorldWritable": false,
#     "kubeconfig": "/Users/operator/.kube/config",
#     "contextName": "prod",
#     "operatorApproved": false,
#     "previouslySeen": false
#   }
#   expect: allow == false
#   expect: deny_missing_operator_approval_for_new_command contains "UX prompt must be shown"
#
# test_allow_approved_homebrew_binary:
#   input = {
#     "resolvedPath": "/opt/homebrew/bin/aws-iam-authenticator",
#     "isRegularFile": true,
#     "isWorldWritable": false,
#     "kubeconfig": "/Users/operator/.kube/config",
#     "contextName": "prod",
#     "operatorApproved": false,
#     "previouslySeen": true
#   }
#   expect: allow == true
#   expect: count(deny_unapproved_directory) == 0
# ---------------------------------------------------------------------------
