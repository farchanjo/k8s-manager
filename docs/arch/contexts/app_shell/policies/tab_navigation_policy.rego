# DDD role: Policy
package k8smanager.app_shell.tab_navigation

# tab_navigation_policy.rego
#
# Machine-enforceable invariants for the multi-document tab system (ADR-0050)
# and the cluster strip (ADR-0051).
#
# This policy enforces structural invariants on the OpenTabsState and
# ClusterStripState aggregates. It is evaluated in CI via conftest against
# serialised JSON representations of these aggregates.
#
# input fields for tab invariants:
#   input.tabs                 — array of DocumentTab objects
#   input.activeTabId          — string | null
#   input.clusterId            — string (UUIDv7)
#
# input fields for cluster strip invariants:
#   input.pins                 — array of ClusterStripPin objects
#
# input fields for tab navigation action:
#   input.action               — "openTab" | "closeTab" | "focusTab" | "pinTab" | "unpinTab"
#   input.tabId                — string (UUIDv7) — the target tab
#   input.isPinned             — bool — current pin state of the tab (for closeTab)

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
# Denial rules — tab invariants
# ---------------------------------------------------------------------------

deny_violations[msg] {
    # INVARIANT T-1: Maximum 20 tabs per cluster.
    count(input.tabs) > 20
    msg := sprintf(
        "tab_navigation.MaxTabsExceeded: cluster %v has %v open tabs (max 20)",
        [input.clusterId, count(input.tabs)],
    )
}

deny_violations[msg] {
    # INVARIANT T-2: tabId must be unique across all tabs.
    tab_ids := [t.tabId | t := input.tabs[_]]
    unique_ids := {id | id := tab_ids[_]}
    count(tab_ids) != count(unique_ids)
    msg := sprintf(
        "tab_navigation.DuplicateTabId: cluster %v contains duplicate tabId values",
        [input.clusterId],
    )
}

deny_violations[msg] {
    # INVARIANT T-3: activeTabId must refer to a tab in the tabs list (when set).
    input.activeTabId != null
    input.activeTabId != ""
    tab_ids := {t.tabId | t := input.tabs[_]}
    not input.activeTabId in tab_ids
    msg := sprintf(
        "tab_navigation.ActiveTabIdOrphan: activeTabId %v not found in tabs list for cluster %v",
        [input.activeTabId, input.clusterId],
    )
}

deny_violations[msg] {
    # INVARIANT T-4: A resourceList or resourceDetail tab MUST carry kindName and apiVersion.
    tab := input.tabs[_]
    tab.tabKind in {"resourceList", "resourceDetail"}
    not tab.kindName
    msg := sprintf(
        "tab_navigation.MissingKindName: tab %v (kind=%v) is missing kindName",
        [tab.tabId, tab.tabKind],
    )
}

deny_violations[msg] {
    # INVARIANT T-4 (continued): apiVersion must also be present.
    tab := input.tabs[_]
    tab.tabKind in {"resourceList", "resourceDetail"}
    not tab.apiVersion
    msg := sprintf(
        "tab_navigation.MissingApiVersion: tab %v (kind=%v) is missing apiVersion",
        [tab.tabId, tab.tabKind],
    )
}

deny_violations[msg] {
    # INVARIANT T-5: Pinned tabs must not be closed via a closeTab action.
    input.action == "closeTab"
    input.isPinned == true
    msg := sprintf(
        "tab_navigation.CannotClosePinnedTab: tab %v is pinned; unpin before closing",
        [input.tabId],
    )
}

deny_violations[msg] {
    # INVARIANT T-6: No cross-cluster mutation through a single tab.
    # A tab's clusterId must match the input.clusterId context.
    tab := input.tabs[_]
    tab.clusterId != input.clusterId
    msg := sprintf(
        "tab_navigation.CrossClusterIsolation: tab %v belongs to cluster %v but state context is %v",
        [tab.tabId, tab.clusterId, input.clusterId],
    )
}

deny_violations[msg] {
    # INVARIANT T-7: drawerWidth, when present, must be in the range [280, 600].
    tab := input.tabs[_]
    tab.drawerWidth
    tab.drawerWidth < 280
    msg := sprintf(
        "tab_navigation.DrawerWidthBelowMin: tab %v drawerWidth %v < 280",
        [tab.tabId, tab.drawerWidth],
    )
}

deny_violations[msg] {
    tab := input.tabs[_]
    tab.drawerWidth
    tab.drawerWidth > 600
    msg := sprintf(
        "tab_navigation.DrawerWidthAboveMax: tab %v drawerWidth %v > 600",
        [tab.tabId, tab.drawerWidth],
    )
}

# ---------------------------------------------------------------------------
# Denial rules — cluster strip invariants
# ---------------------------------------------------------------------------

deny_violations[msg] {
    # INVARIANT S-1: Maximum 16 pins in the cluster strip.
    count(input.pins) > 16
    msg := sprintf(
        "tab_navigation.MaxPinsExceeded: cluster strip has %v pins (max 16)",
        [count(input.pins)],
    )
}

deny_violations[msg] {
    # INVARIANT S-2: colorIndex must be in the range [0, 7].
    pin := input.pins[_]
    pin.colorIndex < 0
    msg := sprintf(
        "tab_navigation.ColorIndexBelowZero: pin %v colorIndex %v < 0",
        [pin.clusterId, pin.colorIndex],
    )
}

deny_violations[msg] {
    pin := input.pins[_]
    pin.colorIndex > 7
    msg := sprintf(
        "tab_navigation.ColorIndexAboveMax: pin %v colorIndex %v > 7",
        [pin.clusterId, pin.colorIndex],
    )
}

deny_violations[msg] {
    # INVARIANT S-3: pinOrder must be unique across all pins.
    pin_orders := [p.pinOrder | p := input.pins[_]]
    unique_orders := {o | o := pin_orders[_]}
    count(pin_orders) != count(unique_orders)
    msg := "tab_navigation.DuplicatePinOrder: cluster strip contains duplicate pinOrder values"
}

deny_violations[msg] {
    # INVARIANT S-4: clusterId must be unique across all pins.
    cluster_ids := [p.clusterId | p := input.pins[_]]
    unique_cluster_ids := {id | id := cluster_ids[_]}
    count(cluster_ids) != count(unique_cluster_ids)
    msg := "tab_navigation.DuplicateClusterId: cluster strip contains duplicate clusterId values"
}

deny_violations[msg] {
    # INVARIANT S-5: providerKind must be a valid enum value.
    valid_providers := {"aks", "eks", "gke", "oidc", "local"}
    pin := input.pins[_]
    not pin.providerKind in valid_providers
    msg := sprintf(
        "tab_navigation.InvalidProviderKind: pin %v providerKind %v is not a valid enum value",
        [pin.clusterId, pin.providerKind],
    )
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# all_violations collects all denial messages for reporting.
all_violations := deny_violations
