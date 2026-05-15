# DDD role: Policy
package k8smanager.app_shell.locale

# locale_policy.rego
#
# Machine-enforceable invariants for app_shell locale management (ADR-0049).
# Validates locale identifier format (ADR-0039 MEDIUM-04), pluralization
# engine selection (ADR-0033), and locale-switch latency bound.
#
# input fields:
#   input.localeIdentifier       — string: BCP 47 locale string to validate
#   input.pluralizationEngine    — "Foundation.NumberFormatter" | "custom"
#   input.localeSwitchLatencyMs  — int: measured latency for locale switch in ms

import future.keywords.if

default allow := false

# BCP 47 subset allowed by ADR-0039 MEDIUM-04 and #LocalePreference.localeIdentifier.
# Pattern: language subtag (2-3 lowercase) + optional script subtag (Title) + optional region (uppercase).
# This mirrors the regex in locale_preference.cue but enforced at policy evaluation time.
valid_locale_pattern := `^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$`

# ---------------------------------------------------------------------------
# Happy-path allow
# ---------------------------------------------------------------------------

allow if {
    count(deny_violations) == 0
}

# ---------------------------------------------------------------------------
# Denial rules
# ---------------------------------------------------------------------------

deny_violations[msg] {
    not re_match(valid_locale_pattern, input.localeIdentifier)
    msg := sprintf(
        "locale identifier %q does not match the BCP 47 subset pattern required by ADR-0039 MEDIUM-04; ICU extensions, numeric region codes, and non-ASCII characters are not permitted",
        [input.localeIdentifier]
    )
}

deny_violations[msg] {
    input.pluralizationEngine != "Foundation.NumberFormatter"
    msg := sprintf(
        "pluralization engine %q is not permitted; only Foundation.NumberFormatter is allowed to ensure CLDR fidelity per ADR-0033",
        [input.pluralizationEngine]
    )
}

deny_violations[msg] {
    input.localeSwitchLatencyMs > 50
    msg := sprintf(
        "locale switch latency %d ms exceeds the 50 ms bound; cached strings must be invalidated within 50 ms of a locale change",
        [input.localeSwitchLatencyMs]
    )
}
