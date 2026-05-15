# DDD role: Policy
package context_navigation.navigation_policy

# navigation_policy.rego
#
# Governs Kubernetes context switching, pinning, and recents management.
# Enforces watch-stream invalidation on context switch, operator approval
# for pinned contexts, and recents list size limits.
#
# input.action               — "switch" | "pin" | "unpin" | "prune_recents"
# input.targetContextName    — string: the context being switched to or pinned
# input.currentContextName   — string: the currently active context
# input.pendingWatchCount    — int: number of active watch streams for the
#                              current context
# input.pinnedContexts       — [string]: list of currently pinned context names
# input.operatorApproved     — bool: operator explicitly approved the pin
#                              action in the settings panel
# input.recentContextsCount  — int: number of entries in the recents list
# input.recentsPruneLimit    — int: max allowed recent entries (default 50)

default allow := false

# ---------------------------------------------------------------------------
# Happy-path: context switch
# Switch is always allowed; pending watches are invalidated by the
# application layer as a post-switch obligation (enforced by audit).
# ---------------------------------------------------------------------------

allow {
    input.action == "switch"
}

# ---------------------------------------------------------------------------
# Happy-path: pin with operator approval
# ---------------------------------------------------------------------------

allow {
    input.action == "pin"
    input.operatorApproved == true
}

# ---------------------------------------------------------------------------
# Happy-path: unpin (no approval required)
# ---------------------------------------------------------------------------

allow {
    input.action == "unpin"
}

# ---------------------------------------------------------------------------
# Happy-path: prune recents when over limit
# ---------------------------------------------------------------------------

allow {
    input.action == "prune_recents"
    input.recentContextsCount > input.recentsPruneLimit
}

# ---------------------------------------------------------------------------
# Deny rules
# ---------------------------------------------------------------------------

deny_pin_without_approval[msg] {
    input.action == "pin"
    input.operatorApproved == false
    msg := sprintf(
        "pin denied: context %q cannot be pinned without explicit operator approval; open Settings → Pinned Contexts to approve",
        [input.targetContextName]
    )
}

deny_prune_within_limit[msg] {
    input.action == "prune_recents"
    input.recentContextsCount <= input.recentsPruneLimit
    msg := sprintf(
        "prune_recents denied: recent contexts count (%d) is within the configured limit (%d); no pruning required",
        [input.recentContextsCount, input.recentsPruneLimit]
    )
}

# ---------------------------------------------------------------------------
# Watch-stream invalidation obligation
# After any successful "switch" action, the application layer MUST
# invalidate all pending watch streams for the previous context before
# registering new watches for the target context.
# This rule is a machine-readable assertion; the application layer enforces it.
# ---------------------------------------------------------------------------

watches_must_be_invalidated_on_switch {
    input.action == "switch"
    input.pendingWatchCount > 0
}

# ---------------------------------------------------------------------------
# Negative test cases
#
# test_deny_pin_without_operator_approval:
#   input = {
#     "action": "pin",
#     "targetContextName": "prod-cluster",
#     "currentContextName": "dev-cluster",
#     "pendingWatchCount": 0,
#     "pinnedContexts": [],
#     "operatorApproved": false,
#     "recentContextsCount": 10,
#     "recentsPruneLimit": 50
#   }
#   expect: allow == false
#   expect: deny_pin_without_approval contains "explicit operator approval"
#
# test_deny_prune_within_limit:
#   input = {
#     "action": "prune_recents",
#     "targetContextName": "",
#     "currentContextName": "dev-cluster",
#     "pendingWatchCount": 0,
#     "pinnedContexts": [],
#     "operatorApproved": false,
#     "recentContextsCount": 30,
#     "recentsPruneLimit": 50
#   }
#   expect: allow == false
#   expect: deny_prune_within_limit contains "within the configured limit"
#
# test_deny_pin_over_recents_limit_without_approval:
#   input = {
#     "action": "pin",
#     "targetContextName": "new-cluster",
#     "currentContextName": "dev-cluster",
#     "pendingWatchCount": 0,
#     "pinnedContexts": [],
#     "operatorApproved": false,
#     "recentContextsCount": 51,
#     "recentsPruneLimit": 50
#   }
#   expect: allow == false
#   expect: deny_pin_without_approval contains "explicit operator approval"
# ---------------------------------------------------------------------------
