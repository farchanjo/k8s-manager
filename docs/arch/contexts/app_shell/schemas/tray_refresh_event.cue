// DDD role: ValueObject
package app_shell

// #TrayRefreshEvent is a sum type representing every discrete lifecycle
// event in the tray refresh state machine. Events are emitted by the
// TrayRefreshScheduler domain service and consumed by the TrayPresenter.
// They are not persisted; they exist only in memory as Combine Subject
// payloads for the duration of the application's run. Logging is
// write-only: events may be appended to an in-memory ring buffer for
// diagnostic purposes but are never written to disk.
//
// No event variant carries credential material, kubeconfig paths, or
// any token-like string that could identify an individual operator.
// The reason field in #RefreshFailed MUST be stripped of credentials
// before the event is emitted.
#TrayRefreshEvent:
	#RefreshRequested |
	#RefreshSucceeded |
	#RefreshFailed |
	#RefreshPaused |
	#RefreshResumed

// #RefreshRequested signals that a refresh cycle should begin. The
// TrayRefreshScheduler emits this event; the TrayPresenter observes it
// and begins issuing PromQL queries and read model reads.
#RefreshRequested: {
	// kind is the discriminator for this sum type variant.
	kind: "refresh_requested"

	// cause identifies what triggered the refresh request. Used by the
	// TrayPresenter to prioritise query ordering (context_switch causes
	// all widgets to reset to loading state before the first result
	// arrives; interval and manual do not reset existing data).
	//
	// "interval"        — the configured interval timer fired.
	// "manual"          — the operator pressed the refresh button in the
	//                      quick actions toolbar.
	// "context_switch"  — the active cluster context changed; all widgets
	//                      must be re-queried against the new cluster.
	// "app_foreground"  — the popover was opened by the operator; the
	//                      TrayRefreshScheduler requests an immediate
	//                      refresh to show current data before the next
	//                      scheduled interval fires.
	cause: "interval" | "manual" | "context_switch" | "app_foreground"
}

// #RefreshSucceeded signals that all widget queries completed without
// error. The TrayPresenter emits this event after writing updated data
// to every widget's view model. The TrayRefreshScheduler uses it to
// record lastRefreshedAtRFC3339 on the #MenuBarTray aggregate.
#RefreshSucceeded: {
	// kind is the discriminator for this sum type variant.
	kind: "refresh_succeeded"

	// durationMillis is the wall-clock time in milliseconds from the
	// emission of the corresponding #RefreshRequested to the completion
	// of the last widget query. Used for performance telemetry and to
	// detect degraded Prometheus response times (threshold: 5000 ms).
	durationMillis: int & >=0

	// widgetCount is the number of widgets that were successfully updated
	// during this cycle. In normal operation this equals the total number
	// of active widgets in the layout. A value lower than expected
	// indicates that some widgets were skipped (e.g. because their
	// PromQL template evaluated to an empty result set).
	widgetCount: int & >=0
}

// #RefreshFailed signals that one or more widget queries could not be
// completed. The TrayPresenter marks affected widgets with a degraded
// indicator (orange badge). Subsequent refresh cycles continue normally;
// the scheduler does not back off unless the cause is a rate-limit error.
//
// IMPORTANT: the reason field MUST NOT contain kubeconfig paths, bearer
// tokens, API server URLs with embedded credentials, or any other
// security-sensitive string. The event producer is responsible for
// stripping such content before emitting this event.
#RefreshFailed: {
	// kind is the discriminator for this sum type variant.
	kind: "refresh_failed"

	// widgetId, when present, identifies the specific widget whose query
	// failed. When absent, the failure is global (e.g. the Prometheus
	// endpoint is unreachable) and all metric widgets are marked as
	// degraded. The widgetId value matches the id field of the
	// corresponding #TrayMetricWidget.
	widgetId?: string & =~"^[a-z][a-z0-9-]*$"

	// reason is a human-readable, credential-free description of the
	// failure suitable for display in the popover tooltip on the degraded
	// widget badge and for logging in the diagnostic ring buffer.
	// Examples: "prometheus_unreachable", "rate_limited", "parse_error",
	// "context_not_found", "metrics_disabled".
	reason!: string
}

// #RefreshPaused signals that the refresh scheduler has suspended all
// activity. No PromQL queries or read model reads will be issued until
// #RefreshResumed is emitted. The TrayPresenter renders a "Paused"
// indicator in the quick actions toolbar.
//
// The TrayRefreshScheduler emits this event in response to system
// conditions. When multiple pause conditions are active simultaneously
// (e.g. lid_closed AND low_power), the scheduler emits a single
// #RefreshPaused with the highest-priority cause (priority order:
// lid_closed > network_unreachable > low_power > operator_pause).
#RefreshPaused: {
	// kind is the discriminator for this sum type variant.
	kind: "refresh_paused"

	// cause identifies the condition that triggered the pause.
	//
	// "lid_closed"          — NSWorkspace.screensDidSleepNotification
	//                          was received; display is off.
	// "low_power"           — ProcessInfo.isLowPowerModeEnabled
	//                          transitioned to true.
	// "network_unreachable" — NWPathMonitor reported a path status of
	//                          .unsatisfied or .requiresConnection.
	// "operator_pause"      — the operator pressed the pause button in
	//                          the quick actions toolbar.
	cause: "lid_closed" | "low_power" | "network_unreachable" | "operator_pause"
}

// #RefreshResumed signals that all active pause conditions have cleared
// and the scheduler is resuming normal operation. The scheduler emits
// this event only after ALL conditions that contributed to the pause
// state have resolved (lid open, power mode normal, network reachable,
// operator unpaused). An immediate #RefreshRequested(cause: interval)
// follows within one scheduler tick.
#RefreshResumed: {
	// kind is the discriminator for this sum type variant.
	kind: "refresh_resumed"
}
