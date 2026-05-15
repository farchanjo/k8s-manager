// DDD role: AggregateRoot
package context_navigation

import (
	"time"
)

// #ActiveContext is the singleton aggregate that records which
// Kubernetes context the operator is currently looking at.
// At most one #ActiveContext exists per application run.
#ActiveContext: {
	// id is a UUIDv7 generated when the aggregate is first
	// materialised. It is stable for the duration of the process
	// but not persisted across launches.
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// contextId is the shared-kernel `ContextId` of the currently
	// active Kubernetes context. Null when the application has
	// just launched and no context has been selected yet.
	contextId?: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// selectedAtRFC3339 is the timestamp of the most recent
	// selection. Used by `RecentContext` to assemble the recents
	// list.
	selectedAtRFC3339?: time.Format(time.RFC3339)

	// selectedBy describes how the active context was chosen.
	// `user` means an explicit selection from the UI; `restored`
	// means the application restored the last-used context at
	// launch; `fallback` means the application defaulted to the
	// kubeconfig-level `current-context` because the last-used
	// value was no longer valid.
	selectedBy?: "user" | "restored" | "fallback"
}
