# DDD role: Policy
package resource_browser.mutation_guard

# DDD role: DomainService
#
# mutation_guard is the Rego policy that governs every mutation
# command dispatched by the resource_browser context. The policy
# evaluates the command against the kind allowlist, the verb closed
# set, confirmation freshness, manifest integrity, and the
# double-confirm requirement for delete operations.
#
# The evaluating adapter (MutationGuardPort) calls this policy with
# the following input shape:
#
#   input.command         — the serialised #MutationCommand
#   input.allowedKinds    — the static list of allowed GVK kind names
#   input.nowSeconds      — the current Unix epoch seconds (integer)
#   input.confirmationIssuedAtSeconds — Unix epoch when the token was
#                           generated in the confirmation modal
#
# Policy result: allow is true when no deny rule fires; the caller
# must treat any populated deny_reasons set as a hard block.
#
# The assistant context (cluster_intelligence) MUST NOT be the source
# of any MutationCommand presented to this policy. Enforcement is
# architectural (the assistant has no access to MutationGuardPort)
# but the policy does not grant a backdoor.

# Default: deny all mutations unless every allow condition is met.
default allow := false

allow {
    count(deny_reasons) == 0
}

# deny_reasons aggregates all active denial messages. The caller
# surfaces these to the operator (for "denied" outcomes) or logs
# them for forensic review.
deny_reasons[msg] { msg := kind_not_allowed }
deny_reasons[msg] { msg := verb_not_allowed }
deny_reasons[msg] { msg := missing_confirmation }
deny_reasons[msg] { msg := missing_manifest_digest }
deny_reasons[msg] { msg := missing_double_confirm_for_delete }
deny_reasons[msg] { msg := confirmation_expired }

# ---------------------------------------------------------------------------
# Rule: kind_not_allowed
#
# The kind declared in the command must appear in the static allowlist
# provided by the adapter from the resource descriptor registry. The
# check is case-sensitive; the allowlist uses PascalCase kind names.
# ---------------------------------------------------------------------------
kind_not_allowed := msg {
    kind := input.command.targetGVK.kind
    not kind_in_allowlist(kind)
    msg := sprintf("kind %q is not in the resource_browser allowlist", [kind])
}

kind_in_allowlist(kind) {
    some i
    input.allowedKinds[i] == kind
}

# ---------------------------------------------------------------------------
# Rule: verb_not_allowed
#
# The commandKind must map to a verb that is in the closed set of
# supported verbs. The mapping below mirrors the #SupportedVerb type
# defined in resource_descriptor.cue.
# ---------------------------------------------------------------------------
verb_not_allowed := msg {
    cmd := input.command.commandKind
    not cmd_kind_is_valid(cmd)
    msg := sprintf("commandKind %q is not in the permitted set", [cmd])
}

cmd_kind_is_valid(cmd) {
    allowed_command_kinds := {
        "ApplyYAML",
        "ScaleReplicas",
        "RolloutRestart",
        "DeleteResource",
        "LabelPatch",
        "AnnotationPatch"
    }
    allowed_command_kinds[cmd]
}

# ---------------------------------------------------------------------------
# Rule: missing_confirmation
#
# Every mutation command must carry a non-empty confirmationToken.
# A confirmation token is a UUIDv7 generated in the confirmation
# modal at the moment the operator interacted with it.
# ---------------------------------------------------------------------------
missing_confirmation := msg {
    not input.command.confirmationToken
    msg := "confirmationToken is missing; operator confirmation is required for all mutations"
}

missing_confirmation := msg {
    input.command.confirmationToken == ""
    msg := "confirmationToken is empty; operator confirmation is required for all mutations"
}

# ---------------------------------------------------------------------------
# Rule: missing_manifest_digest
#
# ApplyYAML commands must carry a manifestDigest field. The digest is
# the SHA-256 of the YAML sent in the request body and is used to
# verify that the manifest was not altered between preview and apply.
# ---------------------------------------------------------------------------
missing_manifest_digest := msg {
    input.command.commandKind == "ApplyYAML"
    not input.command.manifestDigest
    msg := "manifestDigest is required for ApplyYAML commands"
}

missing_manifest_digest := msg {
    input.command.commandKind == "ApplyYAML"
    input.command.manifestDigest == ""
    msg := "manifestDigest must not be empty for ApplyYAML commands"
}

# ---------------------------------------------------------------------------
# Rule: missing_double_confirm_for_delete
#
# DeleteResource commands must carry doubleConfirmed=true. This flag
# is set by the UI layer only after the operator has typed the exact
# resource name into the confirmation text field and pressed the
# destructive action button a second time.
# ---------------------------------------------------------------------------
missing_double_confirm_for_delete := msg {
    input.command.commandKind == "DeleteResource"
    not input.command.doubleConfirmed
    msg := "delete operations require doubleConfirmed=true; operator must type the resource name and confirm twice"
}

missing_double_confirm_for_delete := msg {
    input.command.commandKind == "DeleteResource"
    input.command.doubleConfirmed == false
    msg := "delete operations require doubleConfirmed=true; operator must type the resource name and confirm twice"
}

# ---------------------------------------------------------------------------
# Rule: confirmation_expired
#
# A confirmation token is considered fresh if it was issued within
# the last 300 seconds (5 minutes) relative to input.nowSeconds.
# Expired tokens are rejected to prevent replay of stale confirmations
# (e.g., a backgrounded confirmation modal being submitted long after
# it was shown to the operator).
# ---------------------------------------------------------------------------
confirmation_expired := msg {
    input.command.confirmationToken
    age_seconds := input.nowSeconds - input.confirmationIssuedAtSeconds
    age_seconds > 300
    msg := sprintf(
        "confirmationToken is %d seconds old; tokens expire after 300 seconds",
        [age_seconds]
    )
}
