# DDD role: Policy
package k8smanager.app_shell.docked_terminal

# docked_terminal_policy.rego
#
# Machine-enforceable invariants for the bottom-docked terminal pane
# (ADR-0057) hosted by AppShell beneath the content area.
#
# Policy is evaluated in CI via conftest against serialised JSON
# representations of the `DockedTerminalPaneState` aggregate and against
# inbound `openDockedTerminalTab` action payloads.
#
# input fields for pane-state invariants:
#   input.paneHeight        — number (points) — current pane height
#   input.contentAreaHeight — number (points) — host content-area height
#   input.tabs              — array of DockedTerminalTab objects
#   input.activeTabId       — string (UUIDv7) | null
#   input.clusterPins       — array of pinned cluster IDs (UUIDv7 strings)
#
# input fields for an open-tab action:
#   input.action            — "openDockedTerminalTab"
#   input.tab               — proposed DockedTerminalTab
#
# DockedTerminalTab fields consumed by this policy:
#   tab.id                  — UUIDv7
#   tab.kind                — "podExec" | "nodeDebug" | "containerExec"
#   tab.label               — string
#   tab.clusterId           — UUIDv7 (must reference a pinned cluster)
#   tab.targetNodeName      — string | null (required for kind == "nodeDebug")
#   tab.connectionState     — "opening" | "open" | "closing" | "closed" | "error"

import future.keywords.if
import future.keywords.in

default allow := false

# ---------------------------------------------------------------------------
# Happy-path allow
# ---------------------------------------------------------------------------

allow if {
    count(deny_violations) == 0
}

# ---------------------------------------------------------------------------
# Pane geometry invariants
# ---------------------------------------------------------------------------

deny_violations[msg] {
    # INVARIANT G-1: paneHeight must be at least 120 pt (ADR-0057 chrome spec).
    input.paneHeight < 120
    msg := sprintf(
        "docked_terminal.PaneHeightBelowMin: paneHeight %v < 120 (ADR-0057 minimum)",
        [input.paneHeight],
    )
}

deny_violations[msg] {
    # INVARIANT G-2: paneHeight must not exceed 80% of the content-area height.
    max_height := input.contentAreaHeight * 0.8
    input.paneHeight > max_height
    msg := sprintf(
        "docked_terminal.PaneHeightAboveMax: paneHeight %v > %v (80%% of contentAreaHeight %v)",
        [input.paneHeight, max_height, input.contentAreaHeight],
    )
}

# ---------------------------------------------------------------------------
# Tab identity invariants
# ---------------------------------------------------------------------------

deny_violations[msg] {
    # INVARIANT T-1: tab id must be unique across all open tabs.
    ids := [t.id | t := input.tabs[_]]
    unique_ids := {id | id := ids[_]}
    count(ids) != count(unique_ids)
    msg := "docked_terminal.DuplicateTabId: docked pane contains duplicate tab id values"
}

deny_violations[msg] {
    # INVARIANT T-2: kind must be in the closed set {podExec, nodeDebug, containerExec}.
    valid_kinds := {"podExec", "nodeDebug", "containerExec"}
    tab := input.tabs[_]
    not tab.kind in valid_kinds
    msg := sprintf(
        "docked_terminal.InvalidTabKind: tab %v kind %q is not in {podExec, nodeDebug, containerExec}",
        [tab.id, tab.kind],
    )
}

deny_violations[msg] {
    # INVARIANT T-3: connectionState must be in the closed lifecycle set.
    valid_states := {"opening", "open", "closing", "closed", "error"}
    tab := input.tabs[_]
    not tab.connectionState in valid_states
    msg := sprintf(
        "docked_terminal.InvalidConnectionState: tab %v connectionState %q is not a valid lifecycle state",
        [tab.id, tab.connectionState],
    )
}

deny_violations[msg] {
    # INVARIANT T-4: clusterId must reference a pinned cluster (cluster strip
    # invariant from ADR-0051). A tab whose cluster has been unpinned must be
    # closed, not left orphaned.
    pinned := {p | p := input.clusterPins[_]}
    tab := input.tabs[_]
    not tab.clusterId in pinned
    msg := sprintf(
        "docked_terminal.OrphanedClusterId: tab %v references clusterId %v which is not in the pinned cluster set",
        [tab.id, tab.clusterId],
    )
}

deny_violations[msg] {
    # INVARIANT T-5: at most one nodeDebug tab per (node name, cluster) pair.
    # Multiple debug sessions on the same node create duplicate ephemeral pods
    # and confuse operators. ADR-0057 §Node debug shell flow.
    tab1 := input.tabs[i]
    tab2 := input.tabs[j]
    i < j
    tab1.kind == "nodeDebug"
    tab2.kind == "nodeDebug"
    tab1.clusterId == tab2.clusterId
    tab1.targetNodeName == tab2.targetNodeName
    msg := sprintf(
        "docked_terminal.DuplicateNodeDebug: cluster %v already has a nodeDebug tab for node %v (tabs %v and %v)",
        [tab1.clusterId, tab1.targetNodeName, tab1.id, tab2.id],
    )
}

deny_violations[msg] {
    # INVARIANT T-6: nodeDebug tab MUST carry a targetNodeName.
    tab := input.tabs[_]
    tab.kind == "nodeDebug"
    not tab.targetNodeName
    msg := sprintf(
        "docked_terminal.NodeDebugMissingTarget: tab %v kind=nodeDebug is missing targetNodeName",
        [tab.id],
    )
}

deny_violations[msg] {
    # INVARIANT T-7: when set, activeTabId must reference an open tab.
    input.activeTabId != null
    input.activeTabId != ""
    ids := {t.id | t := input.tabs[_]}
    not input.activeTabId in ids
    msg := sprintf(
        "docked_terminal.ActiveTabIdOrphan: activeTabId %v not found in docked pane tabs list",
        [input.activeTabId],
    )
}

# ---------------------------------------------------------------------------
# Action-level invariants (openDockedTerminalTab)
# ---------------------------------------------------------------------------

deny_violations[msg] {
    # INVARIANT A-1: an openDockedTerminalTab action must carry a tab object.
    input.action == "openDockedTerminalTab"
    not input.tab
    msg := "docked_terminal.MissingActionTab: openDockedTerminalTab action requires a tab payload"
}

deny_violations[msg] {
    # INVARIANT A-2: opening a tab whose clusterId is not pinned is rejected
    # before any TerminalSessionActor is spawned.
    input.action == "openDockedTerminalTab"
    input.tab
    pinned := {p | p := input.clusterPins[_]}
    not input.tab.clusterId in pinned
    msg := sprintf(
        "docked_terminal.OpenForUnpinnedCluster: cannot open docked tab for clusterId %v (not pinned)",
        [input.tab.clusterId],
    )
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

all_violations := deny_violations
