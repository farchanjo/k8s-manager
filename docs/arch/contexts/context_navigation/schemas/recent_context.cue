// DDD role: ReadModel
package context_navigation

import (
	"time"
)

// #RecentContextEntry is one row in the most-recently-used list of
// Kubernetes contexts. The full list is a ReadModel materialised
// from a small set of UserDefaults keys; it is never the
// authoritative store for any business invariant.
#RecentContextEntry: {
	contextId!:        =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
	displayName!:      string
	lastUsedRFC3339!:  time.Format(time.RFC3339)
	useCount!:         int & >=1
	// pinned mirrors the user's pin state for the context. A pinned
	// entry never falls off the recents window.
	pinned!:           bool | *false
}

// #RecentContextWindow is the bounded list maintained by the
// `context_navigation` aggregate. Most-recent first. The window
// holds at most 32 entries; entries beyond that limit are pruned
// from the tail, except for `pinned` entries which are exempt.
#RecentContextWindow: {
	maxEntries!: int & >=8 & <=64 | *32
	entries: [...#RecentContextEntry]
}

// #PinnedContext is a value object capturing one operator-pinned
// Kubernetes context. Pins survive application restarts and
// kubeconfig reloads (as long as the underlying context still
// resolves to the same `ContextId`).
#PinnedContext: {
	contextId!:    =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
	pinnedAtRFC3339!: time.Format(time.RFC3339)
	// displayOrder controls the operator-chosen ordering in the
	// pinned section of the sidebar. Lower values sort first.
	displayOrder!: int & >=0
}
