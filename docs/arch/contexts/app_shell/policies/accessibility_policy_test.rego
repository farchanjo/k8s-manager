# DDD role: PolicyTest
package k8smanager.app_shell.accessibility_test

import data.k8smanager.app_shell.accessibility

# ---------------------------------------------------------------------------
# Allow tests (3 minimum per ADR-0049)
# ---------------------------------------------------------------------------

test_allow_all_controls_labeled_and_contrast_ok if {
    accessibility.allow with input as {
        "controls": [
            {"id": "btn-refresh", "accessibilityLabel": "Refresh cluster view", "colorContrastRatio": 5.2, "isLargeText": false},
            {"id": "lbl-cluster-name", "accessibilityLabel": "Cluster name", "colorContrastRatio": 7.1, "isLargeText": false},
            {"id": "btn-large-action", "accessibilityLabel": "Open settings", "colorContrastRatio": 3.5, "isLargeText": true},
        ],
        "voiceOverOrderMatchesVisual": true,
        "keyboardNavigableActionIds": ["open-command-palette", "refresh-view", "open-settings"],
        "shortcutMapActionIds": ["open-command-palette", "refresh-view", "open-settings"],
    }
}

test_allow_minimal_single_control if {
    accessibility.allow with input as {
        "controls": [
            {"id": "btn-ok", "accessibilityLabel": "OK", "colorContrastRatio": 4.5, "isLargeText": false},
        ],
        "voiceOverOrderMatchesVisual": true,
        "keyboardNavigableActionIds": ["confirm-action"],
        "shortcutMapActionIds": ["confirm-action"],
    }
}

test_allow_large_text_at_minimum_contrast if {
    accessibility.allow with input as {
        "controls": [
            {"id": "heading-1", "accessibilityLabel": "Main heading", "colorContrastRatio": 3.0, "isLargeText": true},
        ],
        "voiceOverOrderMatchesVisual": true,
        "keyboardNavigableActionIds": [],
        "shortcutMapActionIds": [],
    }
}

test_allow_no_shortcut_actions_no_nav_required if {
    accessibility.allow with input as {
        "controls": [
            {"id": "lbl-version", "accessibilityLabel": "App version 1.0", "colorContrastRatio": 6.0, "isLargeText": false},
        ],
        "voiceOverOrderMatchesVisual": true,
        "keyboardNavigableActionIds": [],
        "shortcutMapActionIds": [],
    }
}

# ---------------------------------------------------------------------------
# Deny tests (3 minimum per ADR-0049)
# ---------------------------------------------------------------------------

test_deny_empty_accessibility_label if {
    not accessibility.allow with input as {
        "controls": [
            {"id": "btn-unlabeled", "accessibilityLabel": "", "colorContrastRatio": 5.0, "isLargeText": false},
        ],
        "voiceOverOrderMatchesVisual": true,
        "keyboardNavigableActionIds": [],
        "shortcutMapActionIds": [],
    }
}

test_deny_body_text_low_contrast if {
    not accessibility.allow with input as {
        "controls": [
            {"id": "lbl-subtle", "accessibilityLabel": "Subtle text", "colorContrastRatio": 3.5, "isLargeText": false},
        ],
        "voiceOverOrderMatchesVisual": true,
        "keyboardNavigableActionIds": [],
        "shortcutMapActionIds": [],
    }
}

test_deny_voiceover_order_mismatch if {
    not accessibility.allow with input as {
        "controls": [
            {"id": "btn-ok", "accessibilityLabel": "OK", "colorContrastRatio": 4.5, "isLargeText": false},
        ],
        "voiceOverOrderMatchesVisual": false,
        "keyboardNavigableActionIds": [],
        "shortcutMapActionIds": [],
    }
}

test_deny_shortcut_action_not_keyboard_navigable if {
    not accessibility.allow with input as {
        "controls": [
            {"id": "btn-action", "accessibilityLabel": "Do action", "colorContrastRatio": 5.0, "isLargeText": false},
        ],
        "voiceOverOrderMatchesVisual": true,
        "keyboardNavigableActionIds": ["open-command-palette"],
        "shortcutMapActionIds": ["open-command-palette", "delete-resource"],
    }
}

test_deny_large_text_below_3_contrast if {
    not accessibility.allow with input as {
        "controls": [
            {"id": "lbl-heading", "accessibilityLabel": "Big heading", "colorContrastRatio": 2.8, "isLargeText": true},
        ],
        "voiceOverOrderMatchesVisual": true,
        "keyboardNavigableActionIds": [],
        "shortcutMapActionIds": [],
    }
}

test_deny_violation_message_empty_label if {
    msgs := accessibility.deny_violations with input as {
        "controls": [
            {"id": "btn-bad", "accessibilityLabel": "", "colorContrastRatio": 5.0, "isLargeText": false},
        ],
        "voiceOverOrderMatchesVisual": true,
        "keyboardNavigableActionIds": [],
        "shortcutMapActionIds": [],
    }
    count(msgs) == 1
    some msg in msgs
    contains(msg, "btn-bad")
    contains(msg, "empty accessibilityLabel")
}
