# DDD role: Policy
package resource_browser.resource_mutation

# resource_mutation_policy.rego
#
# Enforces that mutation commands referencing a Kubernetes kind only execute
# operations that are listed in that kind's `ResourceKindDescriptor.permittedOperations`
# field (ADR-0013, ADR-0050). Pairs with `mutation_guard.rego` which enforces the
# command-level confirmation, audit, and freshness invariants.
#
# This policy is consulted before `mutation_guard` to fail-fast when an operator
# attempts to invoke an operation that the kind does not declare. The FAB
# visibility rule from ADR-0066 derives its hide/show decision from the same
# kind-descriptor field this policy enforces.
#
# input.command — the serialised mutation command, shape mirroring
#                 #MutationCommand from `resource_descriptor.cue`:
#   command.commandKind      — "ApplyYAML" | "ScaleReplicas" | "RolloutRestart"
#                              | "DeleteResource" | "CreateFromTemplate"
#                              | "CreateFromClipboard" | "CreateFromFork"
#                              | "LabelPatch" | "AnnotationPatch"
#   command.targetGVK.kind   — PascalCase kind name (e.g. "Deployment", "Node")
#
# input.kindDescriptors — map of {kind: ResourceKindDescriptor}, supplied by the
#                         adapter from the in-process resource descriptor registry.
#   kindDescriptors[kind].permittedOperations — array of operation strings drawn
#                         from the closed set
#                         {"list","get","watch","edit-yaml","delete","events",
#                          "create","scale","rollout-restart","logs","exec"}
#
# Policy result: `allow` is true when no deny rule fires. The caller must treat
# any populated `deny_violations` set as a hard block.

import future.keywords.if
import future.keywords.in

default allow := false

# Verb mapping: each commandKind requires a specific operation token to appear
# in `permittedOperations` for the target kind.
verb_for_command := {
    "ApplyYAML":            "edit-yaml",
    "ScaleReplicas":        "scale",
    "RolloutRestart":       "rollout-restart",
    "DeleteResource":       "delete",
    "CreateFromTemplate":   "create",
    "CreateFromClipboard":  "create",
    "CreateFromFork":       "create",
    "LabelPatch":           "edit-yaml",
    "AnnotationPatch":      "edit-yaml",
}

allow if {
    count(deny_violations) == 0
}

# ---------------------------------------------------------------------------
# Deny rules
# ---------------------------------------------------------------------------

deny_violations[msg] {
    # INVARIANT M-1: targetGVK.kind must be present and non-empty.
    not input.command.targetGVK.kind
    msg := "resource_mutation.MissingTargetKind: command.targetGVK.kind is required"
}

deny_violations[msg] {
    input.command.targetGVK.kind == ""
    msg := "resource_mutation.MissingTargetKind: command.targetGVK.kind is empty"
}

deny_violations[msg] {
    # INVARIANT M-2: commandKind must map to a known verb token.
    cmd := input.command.commandKind
    not verb_for_command[cmd]
    msg := sprintf(
        "resource_mutation.UnknownCommandKind: commandKind %q has no verb mapping",
        [cmd],
    )
}

deny_violations[msg] {
    # INVARIANT M-3: kind must have a descriptor in the registry.
    kind := input.command.targetGVK.kind
    not input.kindDescriptors[kind]
    msg := sprintf(
        "resource_mutation.UnknownKind: kind %q is not present in the resource descriptor registry",
        [kind],
    )
}

deny_violations[msg] {
    # INVARIANT M-4: the kind's permittedOperations MUST include the verb that
    # the commandKind maps to. This is the core gate that ADR-0066 references
    # for the FAB and ADR-0061 references for the per-row action menu.
    kind := input.command.targetGVK.kind
    cmd := input.command.commandKind
    required_verb := verb_for_command[cmd]
    descriptor := input.kindDescriptors[kind]
    not required_verb in descriptor.permittedOperations
    msg := sprintf(
        "resource_mutation.OperationNotPermitted: kind %q does not permit verb %q (commandKind %q); permittedOperations = %v",
        [kind, required_verb, cmd, descriptor.permittedOperations],
    )
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

all_violations := deny_violations
