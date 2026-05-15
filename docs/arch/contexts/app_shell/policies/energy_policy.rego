# DDD role: Policy
package k8smanager.app_shell.energy

# energy_policy.rego
#
# Machine-enforceable invariants for app_shell energy management (ADR-0049).
# Evaluates runtime configuration assertions to detect violations of the
# energy budget defined in ADR-0022 (menu bar tray) and ADR-0021 (app shell).
#
# input fields:
#   input.powerSource              — "battery" | "ac"
#   input.displaySleepActive       — bool: true when macOS screensaver/sleep is active
#   input.trayRefreshIntervalSec   — int: current tray widget refresh interval in seconds
#   input.cpuPercentSustained      — number: measured sustained CPU usage (0–100) at idle

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

deny_violations[msg] {
    input.powerSource == "battery"
    input.trayRefreshIntervalSec < 30
    msg := sprintf(
        "tray refresh interval %d s is below the 30 s minimum required when on battery power",
        [input.trayRefreshIntervalSec]
    )
}

deny_violations[msg] {
    input.powerSource == "ac"
    input.trayRefreshIntervalSec < 5
    msg := sprintf(
        "tray refresh interval %d s is below the 5 s minimum required when on AC power",
        [input.trayRefreshIntervalSec]
    )
}

deny_violations[msg] {
    input.displaySleepActive == true
    input.cpuPercentSustained > 0
    msg := sprintf(
        "background CPU usage %.2f%% detected while display sleep is active; no CPU work is permitted during display sleep",
        [input.cpuPercentSustained]
    )
}

deny_violations[msg] {
    input.cpuPercentSustained > 1
    msg := sprintf(
        "sustained idle CPU usage %.2f%% exceeds the 1%% budget; app_shell must not exceed 1%% CPU at idle",
        [input.cpuPercentSustained]
    )
}
