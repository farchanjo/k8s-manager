// DDD Role: ValueObject
// Bounded context: cluster_connectivity
// Described by: ADR-0025 (per-cluster isolation strategy)
//
// #ClusterSessionEvent is the sum type of all domain events that a
// ClusterSessionActor may publish to observers via AsyncStream.
// All event variants are immutable value objects; they carry no mutable
// references. Observers receive them through the session's event stream.

package cluster_connectivity

// #SessionOpened is published when a ClusterSessionActor successfully
// creates its HTTPClient, establishes the EventLoopGroup, and confirms
// connectivity to the API server (lifecycleState transitions to
// "connected").
#SessionOpened: {
	kind: "SessionOpened"

	// sessionId is the UUIDv7 of the newly opened ClusterSession.
	sessionId: #UUIDv7

	// clusterId is the shared-kernel UUIDv7 of the cluster.
	clusterId: #UUIDv7

	// kubernetesContextId is the UUIDv7 of the kubeconfig context
	// used to open this session.
	kubernetesContextId: #UUIDv7

	// occurredAt is the RFC 3339 timestamp of the event.
	occurredAt: #RFC3339
}

// #SessionDegraded is published when the session is still technically
// open (the HTTPClient and EventLoopGroup are alive) but a required
// capability is unavailable. The most common cause is a missing or
// expired exec-plugin credential; the pool can still issue unauthenticated
// or cached requests but exec-plugin-dependent flows will fail.
#SessionDegraded: {
	kind: "SessionDegraded"

	// sessionId is the UUIDv7 of the affected ClusterSession.
	sessionId: #UUIDv7

	// clusterId is the shared-kernel UUIDv7 of the cluster.
	clusterId: #UUIDv7

	// reason describes the degradation cause at a coarse grain so
	// that the UI can present a targeted affordance to the operator.
	reason: "no-credentials" | "exec-plugin-failed" | "certificate-expired"

	// detail is a human-readable description of the degradation cause.
	// Must not contain credential material.
	detail: string

	// occurredAt is the RFC 3339 timestamp of the event.
	occurredAt: #RFC3339
}

// #SessionDisconnected is published when the session has lost connectivity
// to the API server. The HTTPClient and EventLoopGroup are still alive
// but no requests are being served. The session will attempt to reconnect
// according to its retry policy.
#SessionDisconnected: {
	kind: "SessionDisconnected"

	// sessionId is the UUIDv7 of the affected ClusterSession.
	sessionId: #UUIDv7

	// clusterId is the shared-kernel UUIDv7 of the cluster.
	clusterId: #UUIDv7

	// reason describes the disconnection cause at a coarse grain.
	// "network" — TCP/TLS failure; "server-error" — HTTP 5xx or
	// unexpected close; "operator-pause" — the operator explicitly
	// paused the session from the UI.
	reason: "network" | "server-error" | "operator-pause"

	// detail is a human-readable description safe for UI display.
	// Must not contain credential material.
	detail: string

	// occurredAt is the RFC 3339 timestamp of the event.
	occurredAt: #RFC3339
}

// #SessionTerminated is published when a ClusterSessionActor has
// completed its full teardown: all child tasks are cancelled, all watch
// streams are closed, all exec sessions are terminated, all port-forward
// listeners are unbound, all terminal sessions are closed, the HTTPClient
// is shut down, and the EventLoopGroup is stopped. This is the terminal
// event; no further events are published on this session's stream.
#SessionTerminated: {
	kind: "SessionTerminated"

	// sessionId is the UUIDv7 of the terminated ClusterSession.
	sessionId: #UUIDv7

	// clusterId is the shared-kernel UUIDv7 of the cluster.
	clusterId: #UUIDv7

	// reason describes why the session was terminated.
	// "operator-requested" — the operator explicitly disconnected;
	// "idle-timeout" — aggressiveIdleShutdownMinutes elapsed;
	// "session-cap-exceeded" — the operator opened a 9th cluster
	//   and confirmed closing this one;
	// "application-exit" — the app is shutting down.
	reason: "operator-requested" | "idle-timeout" | "session-cap-exceeded" | "application-exit"

	// occurredAt is the RFC 3339 timestamp of the event.
	occurredAt: #RFC3339
}

// #PoolStatsSnapshot is a periodic heartbeat event published by
// ClusterSessionActor every 30 seconds, carrying a fresh snapshot of
// the HTTPClient connection pool metrics. Consumers (the diagnostics
// panel, the assistant's diagnostic MCP tools) subscribe to this stream
// to power live pool-size indicators without polling.
#PoolStatsSnapshot: {
	kind: "PoolStatsSnapshot"

	// sessionId is the UUIDv7 of the session publishing this snapshot.
	sessionId: #UUIDv7

	// clusterId is the shared-kernel UUIDv7 of the cluster.
	clusterId: #UUIDv7

	// stats is the point-in-time connection pool snapshot.
	stats: #PoolStats

	// occurredAt is the RFC 3339 timestamp when the snapshot was taken.
	occurredAt: #RFC3339
}

// #ClusterSessionEvent is the discriminated union of all event types
// that ClusterSessionActor may emit. Consumers pattern-match on `kind`.
#ClusterSessionEvent:
	#SessionOpened |
	#SessionDegraded |
	#SessionDisconnected |
	#SessionTerminated |
	#PoolStatsSnapshot
