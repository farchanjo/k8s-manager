// DDD role: AggregateRoot
package app_shell

// #CommandPalette is the aggregate root for the universal command palette
// overlay. It owns the open/closed lifecycle, the current query string,
// the selection cursor, and the bounded ring of recent invocations.
//
// The aggregate is hydrated from the local_persistence bounded context under
// the key "app_shell/command_palette". Recent invocations are persisted
// across launches so that the most-used commands appear first on palette
// open before the operator types any query.
//
// The palette is a modal overlay: when isOpen is true it holds full keyboard
// focus. The rest of the window is inert. Esc always closes the palette and
// returns focus to the previously focused element.
#CommandPalette: {
	// id uniquely identifies this aggregate instance. UUIDv7 (time-ordered).
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// isOpen reflects whether the palette overlay is currently presented.
	// Toggle via ⌘P or ⌘K. Dismissed by Esc, command execution, or
	// clicking outside the overlay.
	isOpen!: bool

	// query holds the current incremental search string typed by the
	// operator. Empty string yields the recent-invocations list ranked by
	// frequency × recency. Non-empty triggers fuzzy ranking over the full
	// command catalog union resource names union cluster names union
	// namespace names.
	query!: string

	// selectedIndex is the zero-based cursor position in the current ranked
	// result list. Incremented by ↓ / j, decremented by ↑ / k. Wraps at
	// both ends. ↩ executes the entry at selectedIndex.
	selectedIndex!: int & >=0

	// recentInvocations is a time-ordered ring of at most 50 invocation
	// records. New entries are prepended; oldest are evicted when the ring
	// overflows. Used to seed the unfiltered palette view and to boost
	// ranking for commands the operator uses frequently.
	recentInvocations: [...#CommandInvocation] & {
		_maxLen: 50
	}
}

// #CommandEntry describes a single item that can appear in the command
// palette result list. Entries are statically registered by each bounded
// context at startup and supplemented at runtime by dynamic resource entries
// (pod names, deployment names, namespace names, cluster names).
//
// Static entries live in the command catalog embedded in the app bundle.
// Dynamic entries are synthesised from the cluster_connectivity and
// resource_browser bounded contexts on each palette open.
#CommandEntry: {
	// id is a stable kebab-case slug used as the primary key across the
	// catalog, shortcut map, and invocation history. Must be globally unique.
	id!: string & =~"^[a-z][a-z0-9-]*$"

	// kind classifies how the palette routes the invocation.
	// - navigation: changes the focused panel or selected resource kind.
	// - action: executes an operation against the current or a named resource.
	// - resource_jump: navigates directly to a named Kubernetes resource.
	// - setting: opens a settings panel or toggles a preference.
	kind!: "navigation" | "action" | "resource_jump" | "setting"

	// title is the primary display label. Short, imperative, sentence-case.
	title!: string & =~"^.{1,64}$"

	// subtitle is the optional secondary label rendered in a smaller weight
	// below the title. Used for namespace/cluster qualifiers on resource
	// entries and for shortcut hint text on static entries.
	subtitle?: string & =~"^.{1,128}$"

	// keywords is a list of additional fuzzy-match tokens that do not appear
	// in the UI but improve discoverability. Include common synonyms,
	// abbreviations, and k9s command names.
	keywords: [...string]

	// keyboardShortcut is the optional direct shortcut that invokes this
	// command without opening the palette. Must be registered in
	// #KeyboardShortcutMap with the same commandId.
	keyboardShortcut?: #KeyChord

	// iconSFSymbol is the SF Symbols v5 name rendered as the leading icon
	// in the palette row. Must resolve at runtime on macOS 14+.
	iconSFSymbol!: string

	// requiresContext indicates whether this command is only valid when a
	// specific resource is selected in the resource browser. When true the
	// palette hides this entry if no resource is currently focused.
	requiresContext!: bool
}

// #CommandInvocation is an immutable record of a single palette command
// execution. Stored in the recentInvocations ring on #CommandPalette and
// used for frequency × recency ranking.
#CommandInvocation: {
	// commandId references #CommandEntry.id.
	commandId!: string & =~"^[a-z][a-z0-9-]*$"

	// invokedAt is the RFC 3339 timestamp of the moment the operator pressed ↩.
	invokedAt!: string & =~"^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(Z|[+-]\\d{2}:\\d{2})$"

	// durationMillis is the wall-clock time from palette open to command
	// execution in milliseconds. Used for UX telemetry; not exposed to the
	// operator.
	durationMillis!: int & >=0
}

// #KeyChord describes a keyboard shortcut as a combination of modifiers and
// a single base key. Modifiers are SwiftUI EventModifiers names.
#KeyChord: {
	// modifiers lists zero or more modifier key names. Valid values are the
	// SwiftUI EventModifiers string representations: "command", "option",
	// "shift", "control", "function", "capsLock", "numericPad".
	modifiers: [...("command" | "option" | "shift" | "control" | "function" | "capsLock" | "numericPad")]

	// key is the base key string. Single characters are taken verbatim.
	// Named keys use the SwiftUI KeyEquivalent string: "return", "escape",
	// "delete", "tab", "space", "upArrow", "downArrow", "leftArrow",
	// "rightArrow", "home", "end", "pageUp", "pageDown", "f1"–"f19".
	key!: string & =~"^.{1,16}$"
}

// ---------------------------------------------------------------------------
// Conceptual command catalog (≥30 entries)
// These values document the intended static command catalog embedded in the
// app bundle. They are expressed as concrete CUE values that conform to
// #CommandEntry and serve as the specification source of truth for the
// Swift command registry.
// ---------------------------------------------------------------------------

_catalogApplyYaml: #CommandEntry & {
	id:             "apply-yaml"
	kind:           "action"
	title:          "Apply YAML from file"
	subtitle:       "kubectl apply -f <file>"
	keywords: ["apply", "deploy", "kubectl", "yaml", "manifest"]
	keyboardShortcut: {modifiers: ["command", "option"], key: "a"}
	iconSFSymbol:    "square.and.arrow.down.on.square"
	requiresContext: false
}

_catalogScaleDeployment: #CommandEntry & {
	id:             "scale-deployment"
	kind:           "action"
	title:          "Scale deployment replicas"
	subtitle:       "Set replica count on selected deployment"
	keywords: ["scale", "replicas", "deployment", "resize"]
	iconSFSymbol:    "scalemass"
	requiresContext: true
}

_catalogRestartDeployment: #CommandEntry & {
	id:             "restart-deployment"
	kind:           "action"
	title:          "Restart deployment"
	subtitle:       "kubectl rollout restart"
	keywords: ["restart", "rollout", "bounce", "redeploy"]
	keyboardShortcut: {modifiers: ["command", "option"], key: "r"}
	iconSFSymbol:    "arrow.circlepath"
	requiresContext: true
}

_catalogViewLogs: #CommandEntry & {
	id:             "view-logs"
	kind:           "action"
	title:          "Stream logs"
	subtitle:       "Open live log stream for selected pod"
	keywords: ["logs", "stream", "stdout", "stderr", "tail", "l"]
	keyboardShortcut: {modifiers: [], key: "l"}
	iconSFSymbol:    "text.alignleft"
	requiresContext: true
}

_catalogExecShell: #CommandEntry & {
	id:             "exec-shell"
	kind:           "action"
	title:          "Open exec shell"
	subtitle:       "kubectl exec -it — /bin/sh"
	keywords: ["exec", "shell", "terminal", "sh", "bash", "s"]
	keyboardShortcut: {modifiers: [], key: "s"}
	iconSFSymbol:    "terminal"
	requiresContext: true
}

_catalogDescribeResource: #CommandEntry & {
	id:             "describe-resource"
	kind:           "action"
	title:          "Describe resource"
	subtitle:       "kubectl describe — shows events and conditions"
	keywords: ["describe", "detail", "events", "conditions", "d"]
	keyboardShortcut: {modifiers: [], key: "d"}
	iconSFSymbol:    "doc.text.magnifyingglass"
	requiresContext: true
}

_catalogEditYaml: #CommandEntry & {
	id:             "edit-yaml"
	kind:           "action"
	title:          "Edit YAML in-place"
	subtitle:       "Open YAML editor for selected resource"
	keywords: ["edit", "yaml", "patch", "e"]
	keyboardShortcut: {modifiers: [], key: "e"}
	iconSFSymbol:    "pencil"
	requiresContext: true
}

_catalogPortForward: #CommandEntry & {
	id:             "port-forward"
	kind:           "action"
	title:          "Start port-forward"
	subtitle:       "Tunnel local port to pod/service port"
	keywords: ["port-forward", "tunnel", "forward", "pf", "localhost"]
	keyboardShortcut: {modifiers: ["command", "option"], key: "p"}
	iconSFSymbol:    "arrow.left.arrow.right.circle"
	requiresContext: true
}

_catalogDeleteResource: #CommandEntry & {
	id:             "delete-resource"
	kind:           "action"
	title:          "Delete resource"
	subtitle:       "kubectl delete — requires confirmation"
	keywords: ["delete", "remove", "destroy"]
	keyboardShortcut: {modifiers: ["command"], key: "delete"}
	iconSFSymbol:    "trash"
	requiresContext: true
}

_catalogCopyYaml: #CommandEntry & {
	id:             "copy-yaml"
	kind:           "action"
	title:          "Copy resource YAML"
	subtitle:       "Copy full YAML to clipboard"
	keywords: ["copy", "yaml", "clipboard", "y"]
	keyboardShortcut: {modifiers: [], key: "y"}
	iconSFSymbol:    "doc.on.clipboard"
	requiresContext: true
}

_catalogSwitchContext: #CommandEntry & {
	id:             "switch-context"
	kind:           "navigation"
	title:          "Switch kubeconfig context"
	subtitle:       "Change active cluster context"
	keywords: ["context", "cluster", "kubeconfig", "switch", "ctx"]
	iconSFSymbol:    "arrow.triangle.2.circlepath"
	requiresContext: false
}

_catalogCycleNamespace: #CommandEntry & {
	id:             "cycle-namespace"
	kind:           "navigation"
	title:          "Cycle to next namespace"
	subtitle:       "Ctrl-N cycles through pinned namespaces"
	keywords: ["namespace", "ns", "cycle", "ctrl-n"]
	keyboardShortcut: {modifiers: ["control"], key: "n"}
	iconSFSymbol:    "folder.badge.gearshape"
	requiresContext: false
}

_catalogOpenSettings: #CommandEntry & {
	id:             "open-settings"
	kind:           "setting"
	title:          "Open settings"
	subtitle:       "General, clusters, shortcuts, appearance"
	keywords: ["settings", "preferences", "prefs", "config"]
	keyboardShortcut: {modifiers: ["command"], key: ","}
	iconSFSymbol:    "gearshape"
	requiresContext: false
}

_catalogToggleVimKeys: #CommandEntry & {
	id:             "toggle-vim-keys"
	kind:           "setting"
	title:          "Toggle vim-style j/k navigation"
	subtitle:       "Enable or disable j/k row movement in resource lists"
	keywords: ["vim", "jk", "navigation", "hjkl"]
	iconSFSymbol:    "v.square"
	requiresContext: false
}

_catalogNewTerminal: #CommandEntry & {
	id:             "new-terminal"
	kind:           "action"
	title:          "New terminal tab"
	subtitle:       "Open a new embedded terminal"
	keywords: ["terminal", "tab", "new", "shell"]
	keyboardShortcut: {modifiers: ["command"], key: "t"}
	iconSFSymbol:    "plus.rectangle.on.rectangle"
	requiresContext: false
}

_catalogFilterList: #CommandEntry & {
	id:             "filter-list"
	kind:           "navigation"
	title:          "Filter resource list"
	subtitle:       "Narrow list by label selector or name prefix"
	keywords: ["filter", "search", "label", "selector", "cmd-f"]
	keyboardShortcut: {modifiers: ["command"], key: "f"}
	iconSFSymbol:    "line.3.horizontal.decrease.circle"
	requiresContext: false
}

_catalogRefreshView: #CommandEntry & {
	id:             "refresh-view"
	kind:           "action"
	title:          "Refresh current view"
	subtitle:       "Re-fetch resources from the API server"
	keywords: ["refresh", "reload", "sync", "cmd-r"]
	keyboardShortcut: {modifiers: ["command"], key: "r"}
	iconSFSymbol:    "arrow.clockwise"
	requiresContext: false
}

_catalogHotkeyHelp: #CommandEntry & {
	id:             "hotkey-help"
	kind:           "navigation"
	title:          "Show keyboard shortcuts"
	subtitle:       "Full shortcut reference overlay"
	keywords: ["help", "shortcuts", "keys", "hotkeys", "?"]
	keyboardShortcut: {modifiers: [], key: "?"}
	iconSFSymbol:    "keyboard"
	requiresContext: false
}

_catalogUsedBy: #CommandEntry & {
	id:             "used-by"
	kind:           "navigation"
	title:          "Show used-by references"
	subtitle:       "Owner references and dependant resources"
	keywords: ["used-by", "owners", "dependants", "references", "u"]
	keyboardShortcut: {modifiers: [], key: "u"}
	iconSFSymbol:    "arrow.up.right.and.arrow.down.left.rectangle"
	requiresContext: true
}

_catalogRollbackDeployment: #CommandEntry & {
	id:             "rollback-deployment"
	kind:           "action"
	title:          "Rollback deployment"
	subtitle:       "kubectl rollout undo to previous revision"
	keywords: ["rollback", "undo", "rollout", "revert", "previous"]
	iconSFSymbol:    "arrow.uturn.backward.circle"
	requiresContext: true
}

_catalogViewEvents: #CommandEntry & {
	id:             "view-events"
	kind:           "navigation"
	title:          "View namespace events"
	subtitle:       "Live-updating event stream for current namespace"
	keywords: ["events", "warnings", "stream", "namespace"]
	iconSFSymbol:    "bell.badge"
	requiresContext: false
}

_catalogHelmUpgrade: #CommandEntry & {
	id:             "helm-upgrade"
	kind:           "action"
	title:          "Helm upgrade release"
	subtitle:       "Upgrade an installed Helm release"
	keywords: ["helm", "upgrade", "chart", "release"]
	iconSFSymbol:    "helm"
	requiresContext: false
}

_catalogHelmDiff: #CommandEntry & {
	id:             "helm-diff"
	kind:           "action"
	title:          "Helm diff release"
	subtitle:       "Preview changes before helm upgrade"
	keywords: ["helm", "diff", "preview", "changes", "chart"]
	iconSFSymbol:    "arrow.left.and.right.text.vertical"
	requiresContext: false
}

_catalogViewMetrics: #CommandEntry & {
	id:             "view-metrics"
	kind:           "navigation"
	title:          "Open metrics dashboard"
	subtitle:       "RED method panel for selected resource"
	keywords: ["metrics", "grafana", "red", "latency", "errors", "requests"]
	iconSFSymbol:    "chart.xyaxis.line"
	requiresContext: true
}

_catalogLabelSelector: #CommandEntry & {
	id:             "label-selector"
	kind:           "navigation"
	title:          "Navigate by label selector"
	subtitle:       "Jump to resources matching a label expression"
	keywords: ["label", "selector", "filter", "app=", "env="]
	iconSFSymbol:    "tag"
	requiresContext: false
}

_catalogPinNamespace: #CommandEntry & {
	id:             "pin-namespace"
	kind:           "setting"
	title:          "Pin namespace"
	subtitle:       "Add namespace to the pinned cycle list"
	keywords: ["pin", "namespace", "favourite", "favorite"]
	iconSFSymbol:    "pin"
	requiresContext: false
}

_catalogPinCluster: #CommandEntry & {
	id:             "pin-cluster"
	kind:           "setting"
	title:          "Pin cluster to ⌘1–⌘9 slot"
	subtitle:       "Assign cluster to a numbered shortcut slot"
	keywords: ["pin", "cluster", "cmd1", "cmd2", "slot"]
	iconSFSymbol:    "number.circle"
	requiresContext: false
}

_catalogNodeDebug: #CommandEntry & {
	id:             "node-debug"
	kind:           "action"
	title:          "Open node debug session"
	subtitle:       "kubectl debug node — ephemeral privileged container"
	keywords: ["node", "debug", "ephemeral", "privileged", "s"]
	iconSFSymbol:    "ant.circle"
	requiresContext: true
}

_catalogHistoryBack: #CommandEntry & {
	id:             "history-back"
	kind:           "navigation"
	title:          "Navigate history back"
	subtitle:       "Go to previous resource view"
	keywords: ["back", "history", "previous", "cmd-["]
	keyboardShortcut: {modifiers: ["command"], key: "["}
	iconSFSymbol:    "chevron.backward"
	requiresContext: false
}

_catalogHistoryForward: #CommandEntry & {
	id:             "history-forward"
	kind:           "navigation"
	title:          "Navigate history forward"
	subtitle:       "Go to next resource view"
	keywords: ["forward", "history", "next", "cmd-]"]
	keyboardShortcut: {modifiers: ["command"], key: "]"}
	iconSFSymbol:    "chevron.forward"
	requiresContext: false
}

_catalogTogglePowerUser: #CommandEntry & {
	id:             "toggle-power-user"
	kind:           "setting"
	title:          "Toggle power-user mode"
	subtitle:       "Collapse disclosure layers into dense list view"
	keywords: ["power", "user", "dense", "compact", "disclosure"]
	iconSFSymbol:    "bolt"
	requiresContext: false
}
