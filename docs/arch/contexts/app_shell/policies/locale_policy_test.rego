# DDD role: PolicyTest
package k8smanager.app_shell.locale_test

import data.k8smanager.app_shell.locale

# ---------------------------------------------------------------------------
# Allow tests (3 minimum per ADR-0049)
# ---------------------------------------------------------------------------

test_allow_en_us if {
    locale.allow with input as {
        "localeIdentifier": "en-US",
        "pluralizationEngine": "Foundation.NumberFormatter",
        "localeSwitchLatencyMs": 20,
    }
}

test_allow_pt_br if {
    locale.allow with input as {
        "localeIdentifier": "pt-BR",
        "pluralizationEngine": "Foundation.NumberFormatter",
        "localeSwitchLatencyMs": 5,
    }
}

test_allow_zh_hans if {
    locale.allow with input as {
        "localeIdentifier": "zh-Hans",
        "pluralizationEngine": "Foundation.NumberFormatter",
        "localeSwitchLatencyMs": 30,
    }
}

test_allow_exact_50ms_boundary if {
    locale.allow with input as {
        "localeIdentifier": "es-ES",
        "pluralizationEngine": "Foundation.NumberFormatter",
        "localeSwitchLatencyMs": 50,
    }
}

# ---------------------------------------------------------------------------
# Deny tests (3 minimum per ADR-0049)
# ---------------------------------------------------------------------------

test_deny_icu_extension_locale if {
    not locale.allow with input as {
        "localeIdentifier": "en-US@calendar=buddhist",
        "pluralizationEngine": "Foundation.NumberFormatter",
        "localeSwitchLatencyMs": 10,
    }
}

test_deny_custom_pluralization if {
    not locale.allow with input as {
        "localeIdentifier": "pt-BR",
        "pluralizationEngine": "custom",
        "localeSwitchLatencyMs": 10,
    }
}

test_deny_latency_over_50ms if {
    not locale.allow with input as {
        "localeIdentifier": "en-US",
        "pluralizationEngine": "Foundation.NumberFormatter",
        "localeSwitchLatencyMs": 51,
    }
}

test_deny_non_ascii_locale if {
    not locale.allow with input as {
        "localeIdentifier": "en-ü",
        "pluralizationEngine": "Foundation.NumberFormatter",
        "localeSwitchLatencyMs": 10,
    }
}

test_deny_violation_messages_custom_plural if {
    msgs := locale.deny_violations with input as {
        "localeIdentifier": "en-US",
        "pluralizationEngine": "custom",
        "localeSwitchLatencyMs": 10,
    }
    count(msgs) == 1
    some msg in msgs
    contains(msg, "Foundation.NumberFormatter")
}
