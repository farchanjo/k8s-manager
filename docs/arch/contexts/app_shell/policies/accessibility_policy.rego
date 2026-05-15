# DDD role: Policy
package k8smanager.app_shell.accessibility

# accessibility_policy.rego
#
# Machine-enforceable invariants for app_shell accessibility (ADR-0049).
# Validates VoiceOver label presence, WCAG AA colour-contrast ratios,
# VoiceOver reading-order alignment, and keyboard-navigation completeness.
#
# input fields:
#   input.controls[_].id                 — string: stable control identifier
#   input.controls[_].accessibilityLabel — string: VoiceOver label (must be non-empty)
#   input.controls[_].colorContrastRatio — number: foreground/background contrast ratio
#   input.controls[_].isLargeText        — bool: true if >=18pt regular or >=14pt bold
#   input.voiceOverOrderMatchesVisual     — bool: VoiceOver focus order matches visual reading order
#   input.keyboardNavigableActionIds      — [string]: action IDs reachable via keyboard-only nav
#   input.shortcutMapActionIds            — [string]: action IDs declared in keyboard_shortcut_map.cue

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
# Denial rules
# ---------------------------------------------------------------------------

# All interactive controls must declare a non-empty accessibilityLabel.
deny_violations[msg] {
    some ctrl in input.controls
    ctrl.accessibilityLabel == ""
    msg := sprintf(
        "control %q has an empty accessibilityLabel; all interactive controls must have a non-empty VoiceOver label",
        [ctrl.id]
    )
}

# WCAG AA body text contrast: ratio >= 4.5 for non-large text.
deny_violations[msg] {
    some ctrl in input.controls
    ctrl.isLargeText == false
    ctrl.colorContrastRatio < 4.5
    msg := sprintf(
        "control %q has body-text color contrast ratio %.2f, below the WCAG AA minimum of 4.5 for non-large text",
        [ctrl.id, ctrl.colorContrastRatio]
    )
}

# WCAG AA large text contrast: ratio >= 3.0 for large text (>=18pt regular or >=14pt bold).
deny_violations[msg] {
    some ctrl in input.controls
    ctrl.isLargeText == true
    ctrl.colorContrastRatio < 3.0
    msg := sprintf(
        "control %q has large-text color contrast ratio %.2f, below the WCAG AA minimum of 3.0 for large text",
        [ctrl.id, ctrl.colorContrastRatio]
    )
}

# VoiceOver focus order must match visual reading order.
deny_violations[msg] {
    input.voiceOverOrderMatchesVisual == false
    msg := "VoiceOver focus order does not match the visual reading order; accessibility.feature requires that VoiceOver traversal follows visual layout"
}

# Every action listed in the keyboard shortcut map must be reachable
# via keyboard-only navigation (no mouse required for any shortcut).
deny_violations[msg] {
    some action_id in input.shortcutMapActionIds
    not action_id in input.keyboardNavigableActionIds
    msg := sprintf(
        "action %q is declared in keyboard_shortcut_map.cue but is not reachable via keyboard-only navigation; keyboard navigation must cover all registered shortcut actions",
        [action_id]
    )
}
