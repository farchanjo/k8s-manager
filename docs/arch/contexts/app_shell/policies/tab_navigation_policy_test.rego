# DDD role: PolicyTest
package k8smanager.app_shell.tab_navigation_test

import future.keywords.if
import future.keywords.in
import data.k8smanager.app_shell.tab_navigation

# ---------------------------------------------------------------------------
# Allow tests — valid tab state
# ---------------------------------------------------------------------------

test_allow_empty_tab_list if {
    tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": [],
        "activeTabId": null,
        "pins": [],
    }
}

test_allow_single_resource_list_tab if {
    tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": [{
            "tabId": "01900000-0000-7000-8000-000000000002",
            "clusterId": "01900000-0000-7000-8000-000000000001",
            "tabKind": "resourceList",
            "kindName": "Pod",
            "apiVersion": "v1",
            "namespace": "default",
            "openedAt": "2026-05-16T10:00:00Z",
            "isPinned": false,
        }],
        "activeTabId": "01900000-0000-7000-8000-000000000002",
        "pins": [],
    }
}

test_allow_pinned_tab if {
    tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": [{
            "tabId": "01900000-0000-7000-8000-000000000003",
            "clusterId": "01900000-0000-7000-8000-000000000001",
            "tabKind": "clusterOverview",
            "openedAt": "2026-05-16T10:00:00Z",
            "isPinned": true,
        }],
        "activeTabId": "01900000-0000-7000-8000-000000000003",
        "pins": [],
    }
}

test_allow_valid_strip_pins if {
    tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": [],
        "activeTabId": null,
        "pins": [
            {
                "clusterId": "01900000-0000-7000-8000-000000000010",
                "displayName": "prod-aks",
                "initials": "PA",
                "colorIndex": 0,
                "pinOrder": 0,
                "isPinned": true,
                "providerKind": "aks",
                "pinnedAt": "2026-05-16T09:00:00Z",
            },
            {
                "clusterId": "01900000-0000-7000-8000-000000000011",
                "displayName": "staging-eks",
                "initials": "SE",
                "colorIndex": 1,
                "pinOrder": 1,
                "isPinned": true,
                "providerKind": "eks",
                "pinnedAt": "2026-05-16T09:05:00Z",
            },
        ],
    }
}

test_allow_close_unpinned_tab if {
    tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": [],
        "activeTabId": null,
        "pins": [],
        "action": "closeTab",
        "tabId": "01900000-0000-7000-8000-000000000004",
        "isPinned": false,
    }
}

# ---------------------------------------------------------------------------
# Deny tests — tab invariant violations
# ---------------------------------------------------------------------------

test_deny_max_tabs_exceeded if {
    # Build 21 tabs to trigger the MaxTabsExceeded invariant.
    twenty_one_tabs := [
        {"tabId": sprintf("01900000-0000-7000-8000-0000000000%02d", [i]),
         "clusterId": "01900000-0000-7000-8000-000000000001",
         "tabKind": "clusterOverview",
         "openedAt": "2026-05-16T10:00:00Z",
         "isPinned": false} |
        i := numbers.range(1, 21)[_]
    ]
    not tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": twenty_one_tabs,
        "activeTabId": null,
        "pins": [],
    }
}

test_deny_orphan_active_tab_id if {
    not tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": [],
        "activeTabId": "01900000-0000-7000-8000-000000000099",
        "pins": [],
    }
}

test_deny_missing_kind_name if {
    not tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": [{
            "tabId": "01900000-0000-7000-8000-000000000005",
            "clusterId": "01900000-0000-7000-8000-000000000001",
            "tabKind": "resourceList",
            "apiVersion": "v1",
            "namespace": "default",
            "openedAt": "2026-05-16T10:00:00Z",
            "isPinned": false,
        }],
        "activeTabId": null,
        "pins": [],
    }
}

test_deny_close_pinned_tab if {
    not tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": [],
        "activeTabId": null,
        "pins": [],
        "action": "closeTab",
        "tabId": "01900000-0000-7000-8000-000000000006",
        "isPinned": true,
    }
}

test_deny_cross_cluster_tab if {
    not tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": [{
            "tabId": "01900000-0000-7000-8000-000000000007",
            "clusterId": "01900000-0000-7000-8000-000000000099",
            "tabKind": "clusterOverview",
            "openedAt": "2026-05-16T10:00:00Z",
            "isPinned": false,
        }],
        "activeTabId": null,
        "pins": [],
    }
}

# ---------------------------------------------------------------------------
# Deny tests — cluster strip invariant violations
# ---------------------------------------------------------------------------

test_deny_invalid_color_index if {
    not tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": [],
        "activeTabId": null,
        "pins": [{
            "clusterId": "01900000-0000-7000-8000-000000000010",
            "displayName": "bad-color",
            "initials": "BC",
            "colorIndex": 8,
            "pinOrder": 0,
            "isPinned": true,
            "providerKind": "local",
            "pinnedAt": "2026-05-16T09:00:00Z",
        }],
    }
}

test_deny_duplicate_pin_order if {
    not tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": [],
        "activeTabId": null,
        "pins": [
            {
                "clusterId": "01900000-0000-7000-8000-000000000010",
                "displayName": "cluster-a",
                "initials": "CA",
                "colorIndex": 0,
                "pinOrder": 0,
                "isPinned": true,
                "providerKind": "local",
                "pinnedAt": "2026-05-16T09:00:00Z",
            },
            {
                "clusterId": "01900000-0000-7000-8000-000000000011",
                "displayName": "cluster-b",
                "initials": "CB",
                "colorIndex": 1,
                "pinOrder": 0,
                "isPinned": true,
                "providerKind": "local",
                "pinnedAt": "2026-05-16T09:01:00Z",
            },
        ],
    }
}

test_deny_invalid_provider_kind if {
    not tab_navigation.allow with input as {
        "clusterId": "01900000-0000-7000-8000-000000000001",
        "tabs": [],
        "activeTabId": null,
        "pins": [{
            "clusterId": "01900000-0000-7000-8000-000000000010",
            "displayName": "bad-provider",
            "initials": "BP",
            "colorIndex": 2,
            "pinOrder": 0,
            "isPinned": true,
            "providerKind": "unknown_provider",
            "pinnedAt": "2026-05-16T09:00:00Z",
        }],
    }
}
