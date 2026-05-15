// DDD role: AggregateRoot
// ADR: ADR-0032 — Toast notification system
//
// Defines the #ToastStack aggregate, #Toast value object, #ToastAction
// value object, and #ToastHistoryEntry read model used by the global
// toast notification overlay.
//
// UUIDv7 regex used throughout:
//   ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$

package app_shell

import (
	"time"
	"strings"
)

// _uuidv7Pattern is the canonical UUIDv7 validation regex.
_uuidv7Pattern: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

// _rfcTimestamp validates RFC3339 datetime strings.
_rfcTimestamp: string & =~time.RFC3339

// -----------------------------------------------------------------------
// #ToastStack — AggregateRoot
// -----------------------------------------------------------------------
// Owns the lifecycle of all active toasts and enforces the stack
// invariants (max concurrent, FIFO drop, position). Persisted to
// local_persistence under `app_shell/toast_stack`. The @Observable
// Swift class wrapping this aggregate is `ToastStack` on @MainActor.

#ToastStack: {
	// id is the persistent identity of this stack instance.
	id: string & _uuidv7Pattern

	// position is the screen corner where the toast stack is anchored.
	// Default: bottom_right. Operator-configurable in Settings → Notifications.
	position: "bottom_right" | "bottom_left" | "top_right" | "top_left"
	position: *"bottom_right" | _

	// maxConcurrent is the maximum number of toasts shown simultaneously.
	// When a new toast arrives and the stack is full, the oldest non-pinned
	// toast is immediately dismissed (FIFO drop).
	// Default: 5.
	maxConcurrent: int & >=1 & <=10
	maxConcurrent: *5 | _

	// activeToasts holds the currently visible toasts, newest-first.
	// Invariant (enforced in Swift): len(activeToasts) <= maxConcurrent.
	activeToasts: [...#Toast]

	// queue holds toasts that are waiting to be shown because the stack
	// is at capacity and all active toasts are pinned.
	queue: [...#Toast]
}

// -----------------------------------------------------------------------
// #Toast — ValueObject
// -----------------------------------------------------------------------
// Represents a single notification card. Immutable after creation.

#Toast: {
	// id is the unique identity of this toast. Assigned by ToastEmitter.
	id: string & _uuidv7Pattern

	// title is the primary notification text.
	// Max 60 characters.
	title: string & strings.MinRunes(1) & strings.MaxRunes(60)

	// message is the optional secondary text.
	// Max 200 characters.
	message?: string & strings.MinRunes(1) & strings.MaxRunes(200)

	// severity determines background tint, icon, and auto-dismiss delay.
	//   success — statusHealthy tint; auto-dismiss 3 000 ms
	//   info    — accentBrand tint; auto-dismiss 3 000 ms
	//   warning — statusWarning tint; auto-dismiss 5 000 ms
	//   error   — statusError tint; auto-dismiss 8 000 ms
	//   neutral — textTertiary tint; auto-dismiss 4 000 ms
	severity: "success" | "info" | "warning" | "error" | "neutral"

	// iconSymbolName is the optional SF Symbol name for the toast icon.
	// When absent, the default severity icon is used:
	//   success → "checkmark.circle.fill"
	//   info    → "info.circle.fill"
	//   warning → "exclamationmark.triangle.fill"
	//   error   → "xmark.octagon.fill"
	//   neutral → "bell.fill"
	iconSymbolName?: string & strings.MinRunes(1)

	// emittedAtRFC3339 records when the toast was enqueued.
	emittedAtRFC3339: _rfcTimestamp

	// autoDismissMs is computed from severity. Expressed in milliseconds.
	// When pinned == true this value is ignored.
	//   success → 3000
	//   info    → 3000
	//   warning → 5000
	//   error   → 8000
	//   neutral → 4000
	autoDismissMs: int & >0

	// Enforce severity-to-autoDismissMs mapping.
	if severity == "success" {autoDismissMs: 3000}
	if severity == "info" {autoDismissMs: 3000}
	if severity == "warning" {autoDismissMs: 5000}
	if severity == "error" {autoDismissMs: 8000}
	if severity == "neutral" {autoDismissMs: 4000}

	// pinned prevents auto-dismiss. The operator must manually dismiss.
	// The ToastEmitter may set this to true for operator-initiated pin,
	// or the toast action can pin it programmatically.
	pinned: bool
	pinned: *false | _

	// action is the optional call-to-action button.
	// See #ToastAction.
	action?: #ToastAction
}

// -----------------------------------------------------------------------
// #ToastAction — ValueObject
// -----------------------------------------------------------------------
// An optional action button rendered in the bottom-right of the toast card.

#ToastAction: {
	// label is the button text. Max 24 characters.
	label: string & strings.MinRunes(1) & strings.MaxRunes(24)

	// actionId is a kebab-case slug identifying the handler.
	// Registered action IDs:
	//   mutation.undo    — undo the last mutation within its 5 s window
	//   audit.view       — navigate to the mutation's audit log entry
	//   cluster.retry    — retry failed cluster connection
	//   kubeconfig.retry — retry failed kubeconfig reload
	//   provider.view    — navigate to Settings → Providers
	//   export.view      — navigate to the exported diagnostics bundle
	actionId: string & =~"^[a-z][a-z0-9]*([.][a-z][a-z0-9]*)*$"

	// payload carries the key-value context needed to execute the action.
	// All values are strings. No credential material may appear here.
	payload: {[string]: string}
}

// -----------------------------------------------------------------------
// #ToastHistoryEntry — ReadModel
// -----------------------------------------------------------------------
// Persisted to the `toast_history` SQLite table (storage.dbml).
// Retains the last 100 entries. Surfaces in Settings → Activity Log.

#ToastHistoryEntry: {
	// id matches the #Toast.id of the source toast.
	id: string & _uuidv7Pattern

	// title, message, severity, iconSymbolName mirror #Toast.
	title:           string & strings.MaxRunes(60)
	message?:        string & strings.MaxRunes(200)
	severity:        "success" | "info" | "warning" | "error" | "neutral"
	iconSymbolName?: string

	// emittedAtRFC3339 matches #Toast.emittedAtRFC3339.
	emittedAtRFC3339: _rfcTimestamp

	// actionId and actionPayloadJson record the action if one was present.
	// actionPayloadJson is JSON-encoded {[string]: string}.
	actionId?:          string
	actionPayloadJson?: string

	// pinned records whether the toast was pinned when dismissed.
	pinned: bool

	// dismissedAtRFC3339 records when the toast was dismissed.
	// Null when the entry represents a toast that was FIFO-dropped
	// before the operator saw it (the entry is still recorded).
	dismissedAtRFC3339?: _rfcTimestamp
}

// -----------------------------------------------------------------------
// Retention invariant
// -----------------------------------------------------------------------
// The PersistenceActor enforces: at most 100 #ToastHistoryEntry rows.
// On each insert, any rows beyond the 100 oldest are deleted.
// This is not expressible as a CUE constraint but is documented here
// as a schema-level note for the migration author.
//
// SQLite enforcement: application-level DELETE after INSERT targeting
// rows where emitted_at_rfc3339 < (SELECT emitted_at_rfc3339 FROM
// toast_history ORDER BY emitted_at_rfc3339 DESC LIMIT 1 OFFSET 99)
