// DDD role: AggregateRoot
package app_shell

// #MenuBarTray is the aggregate root for the system menu bar status item
// and its associated popover. It captures the operator-configured refresh
// policy, the current icon appearance state, and the transient lifecycle
// state of the popover. The aggregate is persisted in the local_persistence
// bounded context under the key "app_shell/menu_bar_tray" with schema
// version "v1". On cold launch the TrayRefreshScheduler domain service
// restores this value and installs the NSStatusItem.
//
// Identifiers are UUIDv7 (time-ordered) for consistency with other
// aggregate roots in this bounded context.
#MenuBarTray: {
	// id uniquely identifies this tray configuration snapshot. Generated
	// once at first launch; never changes for the lifetime of the
	// installation. Used as the stable key when logging tray lifecycle
	// events to the audit trail.
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// displayMode controls whether the tray reflects only the active
	// cluster (the default) or aggregates health and metrics across all
	// known clusters simultaneously.
	//
	// "active_cluster" — all widgets are scoped to the cluster that is
	//   currently active in context_navigation. Switching the active
	//   context (via the header Picker or the main window sidebar) causes
	//   the tray to re-issue a RefreshRequested(cause: context_switch)
	//   immediately.
	//
	// "all_clusters_summary" — widgets use aggregated PromQL expressions
	//   that span all configured Prometheus endpoints. The header shows a
	//   composite health indicator instead of a single-context picker.
	//   The operator enables this in Settings > Tray.
	displayMode: "active_cluster" | "all_clusters_summary" | *"active_cluster"

	// iconState encodes the visual appearance of the NSStatusItem button.
	// The value is computed by the TrayPresenter from the active cluster's
	// health (or the worst-case health across all clusters in
	// all_clusters_summary mode) after each refresh cycle.
	//
	// "online"   — cluster is reachable and healthy; template image
	//               rendered at full opacity with no overlay.
	// "degraded" — cluster is reachable but one or more nodes or system
	//               components report a warning condition; an orange filled
	//               circle overlay is composited over the template image.
	// "offline"  — cluster is unreachable or the last refresh failed with
	//               a non-transient error; the template image is rendered
	//               at reduced opacity (system dimmed appearance).
	iconState: "online" | "degraded" | "offline" | *"online"

	// refreshIntervalSeconds is the period between automatic refresh
	// cycles when the interval timer is active. Valid values are 5, 15,
	// 30, and 60. The TrayRefreshScheduler domain service uses this value
	// to configure its Combine Timer.publish(every:) publisher.
	//
	// When backgroundRefreshEnabled is true and the popover is closed,
	// the effective interval is doubled (e.g. 30 → 60 s) to reduce
	// background network traffic.
	refreshIntervalSeconds: 5 | 15 | 30 | 60 | *30

	// manualRefreshOnly disables the interval timer entirely when true.
	// Refresh only occurs when the operator explicitly presses the refresh
	// button in the quick actions toolbar, or when the popover opens, or
	// when the active context changes. Overrides refreshIntervalSeconds.
	manualRefreshOnly: bool | *false

	// backgroundRefreshEnabled controls whether Combine subscriptions and
	// the interval timer persist after the operator closes the popover.
	// When false (the default), all subscriptions are cancelled on
	// popoverDidClose. When true, the interval timer subscription is
	// retained and fires at twice the configured interval to limit
	// background network load. The operator must acknowledge the
	// disclosure notice in Settings > Tray before this can be set to true.
	backgroundRefreshEnabled: bool | *false

	// popoverPinned controls whether the popover remains visible when
	// keyboard or mouse focus moves to another application. When false
	// (the default), the popover is transient and closes on
	// resignKeyWindow. When true, the popover behaves as a non-transient
	// panel and remains on screen until the operator explicitly dismisses
	// it or presses Escape. Useful when monitoring a deployment rollout
	// while working in a terminal.
	popoverPinned: bool | *false

	// lastRefreshedAtRFC3339 is the ISO 8601 timestamp of the most recent
	// successful refresh cycle. It is absent before the first successful
	// refresh. Stored in UTC. The TrayPresenter formats this as a relative
	// duration string (e.g. "last checked 12s ago") for display in the
	// popover header below the status badge.
	lastRefreshedAtRFC3339?: string & =~"^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?Z$"

	// popoverState is the transient lifecycle state of the NSPopover. This
	// field is not persisted; it is reconstructed as "closed" on every
	// cold launch. The TrayRefreshScheduler observes transitions from
	// "closed" to "opening" to start subscriptions and from "open" to
	// "closing" to cancel subscriptions (when backgroundRefreshEnabled is
	// false).
	popoverState: "closed" | "opening" | "open" | "closing" | *"closed"
}
