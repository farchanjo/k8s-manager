# DDD role: PolicyTest
package k8smanager.app_shell.energy_test

import future.keywords.if
import future.keywords.in
import data.k8smanager.app_shell.energy

# ---------------------------------------------------------------------------
# Allow tests (3 minimum per ADR-0049)
# ---------------------------------------------------------------------------

test_allow_battery_30s_refresh if {
    energy.allow with input as {
        "powerSource": "battery",
        "displaySleepActive": false,
        "trayRefreshIntervalSec": 30,
        "cpuPercentSustained": 0.3,
    }
}

test_allow_ac_10s_refresh if {
    energy.allow with input as {
        "powerSource": "ac",
        "displaySleepActive": false,
        "trayRefreshIntervalSec": 10,
        "cpuPercentSustained": 0.5,
    }
}

test_allow_battery_long_interval_zero_cpu if {
    energy.allow with input as {
        "powerSource": "battery",
        "displaySleepActive": false,
        "trayRefreshIntervalSec": 60,
        "cpuPercentSustained": 0.0,
    }
}

test_allow_display_sleep_zero_cpu if {
    energy.allow with input as {
        "powerSource": "battery",
        "displaySleepActive": true,
        "trayRefreshIntervalSec": 30,
        "cpuPercentSustained": 0.0,
    }
}

# ---------------------------------------------------------------------------
# Deny tests (3 minimum per ADR-0049)
# ---------------------------------------------------------------------------

test_deny_battery_too_frequent if {
    not energy.allow with input as {
        "powerSource": "battery",
        "displaySleepActive": false,
        "trayRefreshIntervalSec": 10,
        "cpuPercentSustained": 0.3,
    }
}

test_deny_ac_sub_5s if {
    not energy.allow with input as {
        "powerSource": "ac",
        "displaySleepActive": false,
        "trayRefreshIntervalSec": 3,
        "cpuPercentSustained": 0.5,
    }
}

test_deny_cpu_during_display_sleep if {
    not energy.allow with input as {
        "powerSource": "battery",
        "displaySleepActive": true,
        "trayRefreshIntervalSec": 30,
        "cpuPercentSustained": 0.5,
    }
}

test_deny_cpu_over_budget_at_idle if {
    not energy.allow with input as {
        "powerSource": "ac",
        "displaySleepActive": false,
        "trayRefreshIntervalSec": 5,
        "cpuPercentSustained": 1.5,
    }
}

test_deny_violations_message_battery if {
    msgs := energy.deny_violations with input as {
        "powerSource": "battery",
        "displaySleepActive": false,
        "trayRefreshIntervalSec": 10,
        "cpuPercentSustained": 0.3,
    }
    count(msgs) == 1
    some msg in msgs
    contains(msg, "below the 30 s minimum")
}
