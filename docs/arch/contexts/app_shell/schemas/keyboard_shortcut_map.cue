// DDD role: ValueObject
package app_shell

// #KeyboardShortcutMap is a value object that enumerates all keyboard
// shortcut bindings for the application shell. It is immutable at runtime
// (bindings are fixed in the app bundle; the operator may not rebind them
// in this version). The map is referenced by #CommandEntry.keyboardShortcut
// and consumed by the SwiftUI .keyboardShortcut modifier registrations at
// app startup.
//
// Scope semantics:
//   global          — active in every window state and panel focus
//   resource_browser — active only when a resource list row holds key focus
//                      and focus is NOT inside a text field or terminal pane
//   terminal        — active when an embedded TerminalSession pane has focus
//   helm            — active when the Helm management panel has focus
//   metrics         — active when the metrics/observability dashboard has focus
//   analytics       — active when the cluster analytics / intelligence panel
//                      has focus
//
// whenContext is an optional predicate string evaluated by the runtime
// focus engine. Expressed as a dot-path into the application focus state
// tree (e.g. "resource.kind == Pod" restricts a binding to pod list rows
// only). Empty means the scope alone determines activation.
#KeyboardShortcutMap: {
	// bindings is the ordered list of all registered shortcut bindings.
	// Order is cosmetic (help overlay display order) only; activation is
	// determined by scope and whenContext at runtime.
	bindings!: [...#ShortcutBinding]
}

// #ShortcutBinding associates a #KeyChord with a command entry within a
// specific scope and optional predicate context.
#ShortcutBinding: {
	// id is a stable kebab-case slug. Used as the primary key for the
	// binding in the help overlay and in automated shortcut-conflict checks.
	id!: string & =~"^[a-z][a-z0-9-]*$"

	// commandId references #CommandEntry.id and determines what action is
	// executed when the chord is pressed.
	commandId!: string & =~"^[a-z][a-z0-9-]*$"

	// keyChord is the keyboard combination that triggers this binding.
	keyChord!: #KeyChord

	// scope determines which panel focus state activates this binding.
	scope!: "global" | "resource_browser" | "terminal" | "helm" | "metrics" | "analytics"

	// whenContext is an optional runtime predicate. When non-empty the
	// binding is only active if the predicate evaluates to true against the
	// current application focus state. Used to scope single-key bindings to
	// specific resource kinds (e.g. restrict node-debug to Node resources).
	whenContext?: string

	// description is the human-readable label shown in the hotkey help
	// overlay. Imperative sentence, no trailing period, ≤80 chars.
	description!: string & =~"^.{1,80}$"
}

// ---------------------------------------------------------------------------
// Concrete shortcut map instance (≥25 bindings)
// This value conforms to #KeyboardShortcutMap and serves as the specification
// source of truth for the Swift ShortcutRegistry initialisation.
// ---------------------------------------------------------------------------

applicationShortcutMap: #KeyboardShortcutMap & {
	bindings: [
		// --- Global bindings -----------------------------------------------

		{
			id:          "global-command-palette-primary"
			commandId:   "open-command-palette"
			keyChord: {modifiers: ["command"], key: "p"}
			scope:       "global"
			description: "Open command palette (primary)"
		},
		{
			id:          "global-command-palette-alternate"
			commandId:   "open-command-palette"
			keyChord: {modifiers: ["command"], key: "k"}
			scope:       "global"
			description: "Open command palette (alternate)"
		},
		{
			id:          "global-refresh"
			commandId:   "refresh-view"
			keyChord: {modifiers: ["command"], key: "r"}
			scope:       "global"
			description: "Refresh current view"
		},
		{
			id:          "global-filter"
			commandId:   "filter-list"
			keyChord: {modifiers: ["command"], key: "f"}
			scope:       "global"
			description: "Filter resource list by name or label selector"
		},
		{
			id:          "global-new-terminal"
			commandId:   "new-terminal"
			keyChord: {modifiers: ["command"], key: "t"}
			scope:       "global"
			description: "Open new embedded terminal tab"
		},
		{
			id:          "global-reopen-terminal"
			commandId:   "reopen-closed-terminal"
			keyChord: {modifiers: ["command", "shift"], key: "t"}
			scope:       "global"
			description: "Reopen most recently closed terminal tab"
		},
		{
			id:          "global-close-panel"
			commandId:   "close-active-panel"
			keyChord: {modifiers: ["command"], key: "w"}
			scope:       "global"
			description: "Close active panel or tab"
		},
		{
			id:          "global-settings"
			commandId:   "open-settings"
			keyChord: {modifiers: ["command"], key: ","}
			scope:       "global"
			description: "Open application settings"
		},
		{
			id:          "global-delete-resource"
			commandId:   "delete-resource"
			keyChord: {modifiers: ["command"], key: "delete"}
			scope:       "global"
			description: "Delete selected resource (requires confirmation)"
		},
		{
			id:          "global-history-back"
			commandId:   "history-back"
			keyChord: {modifiers: ["command"], key: "["}
			scope:       "global"
			description: "Navigate to previous resource view"
		},
		{
			id:          "global-history-forward"
			commandId:   "history-forward"
			keyChord: {modifiers: ["command"], key: "]"}
			scope:       "global"
			description: "Navigate to next resource view"
		},
		{
			id:          "global-cluster-1"
			commandId:   "switch-pinned-cluster-1"
			keyChord: {modifiers: ["command"], key: "1"}
			scope:       "global"
			description: "Switch to pinned cluster slot 1"
		},
		{
			id:          "global-cluster-2"
			commandId:   "switch-pinned-cluster-2"
			keyChord: {modifiers: ["command"], key: "2"}
			scope:       "global"
			description: "Switch to pinned cluster slot 2"
		},
		{
			id:          "global-cluster-3"
			commandId:   "switch-pinned-cluster-3"
			keyChord: {modifiers: ["command"], key: "3"}
			scope:       "global"
			description: "Switch to pinned cluster slot 3"
		},

		// --- Resource browser single-key bindings --------------------------
		// These are active only when a resource list row has key focus and
		// no text field or terminal pane intercepts the event.

		{
			id:          "browser-view-logs"
			commandId:   "view-logs"
			keyChord: {modifiers: [], key: "l"}
			scope:       "resource_browser"
			description: "Stream logs for selected pod or container"
		},
		{
			id:          "browser-exec-shell"
			commandId:   "exec-shell"
			keyChord: {modifiers: [], key: "s"}
			scope:       "resource_browser"
			description: "Open exec shell in selected pod"
		},
		{
			id:          "browser-describe"
			commandId:   "describe-resource"
			keyChord: {modifiers: [], key: "d"}
			scope:       "resource_browser"
			description: "Describe selected resource"
		},
		{
			id:          "browser-edit-yaml"
			commandId:   "edit-yaml"
			keyChord: {modifiers: [], key: "e"}
			scope:       "resource_browser"
			description: "Open YAML editor for selected resource"
		},
		{
			id:          "browser-used-by"
			commandId:   "used-by"
			keyChord: {modifiers: [], key: "u"}
			scope:       "resource_browser"
			description: "Show owner references and dependant resources"
		},
		{
			id:          "browser-copy-yaml"
			commandId:   "copy-yaml"
			keyChord: {modifiers: [], key: "y"}
			scope:       "resource_browser"
			description: "Copy resource YAML to clipboard"
		},
		{
			id:          "browser-command-mode"
			commandId:   "enter-command-mode"
			keyChord: {modifiers: [], key: ":"}
			scope:       "resource_browser"
			description: "Enter colon command mode"
		},
		{
			id:          "browser-inline-search"
			commandId:   "inline-search"
			keyChord: {modifiers: [], key: "/"}
			scope:       "resource_browser"
			description: "Activate inline search within resource list"
		},
		{
			id:          "browser-hotkey-help"
			commandId:   "hotkey-help"
			keyChord: {modifiers: [], key: "?"}
			scope:       "resource_browser"
			description: "Show keyboard shortcut help overlay"
		},
		{
			id:          "browser-cycle-namespace"
			commandId:   "cycle-namespace"
			keyChord: {modifiers: ["control"], key: "n"}
			scope:       "resource_browser"
			description: "Cycle to next pinned namespace"
		},

		// --- Node-specific action (predicate-gated) ------------------------

		{
			id:          "browser-node-debug"
			commandId:   "node-debug"
			keyChord: {modifiers: [], key: "s"}
			scope:       "resource_browser"
			whenContext: "resource.kind == Node"
			description: "Open privileged node debug session"
		},

		// --- Apply YAML global action --------------------------------------

		{
			id:          "global-apply-yaml"
			commandId:   "apply-yaml"
			keyChord: {modifiers: ["command", "option"], key: "a"}
			scope:       "global"
			description: "Apply YAML manifest from file picker"
		},

		// --- Port-forward global action ------------------------------------

		{
			id:          "global-port-forward"
			commandId:   "port-forward"
			keyChord: {modifiers: ["command", "option"], key: "p"}
			scope:       "global"
			description: "Start port-forward tunnel to selected pod or service"
		},

		// --- Restart deployment global action ------------------------------

		{
			id:          "global-restart-deployment"
			commandId:   "restart-deployment"
			keyChord: {modifiers: ["command", "option"], key: "r"}
			scope:       "global"
			description: "Restart selected deployment via rollout restart"
		},
	]
}
