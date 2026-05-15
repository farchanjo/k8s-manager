// DDD role: ValueObject
package cluster_connectivity

import (
	"time"
)

// #HealthStatus is the immutable result of a single cluster health
// probe. The domain service `ClusterHealthProbe` produces one
// instance per probe; consumers should treat it as read-only.
#HealthStatus: {
	clusterId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
	probedAt!:  time.Format(time.RFC3339)
	state!:     #HealthState
	// latencyMillis is the wall-clock latency of the probe round-trip.
	// Absent when the probe failed before establishing a connection.
	latencyMillis?: int & >=0
	// detail is an operator-facing human-readable explanation.
	// It MUST NOT contain credential material, kubeconfig paths, or
	// internal token fingerprints.
	detail?: string
}

#HealthState:
	// "reachable" — probe completed and the API server returned 200 on /readyz or /healthz
	"reachable" |
	// "degraded" — probe completed but health endpoint reported non-200 or partial readiness
	"degraded" |
	// "unreachable" — network or TLS error before a response was received
	"unreachable" |
	// "unauthorized" — 401 from the API server
	"unauthorized" |
	// "forbidden" — 403 from the API server (auth succeeded but lacks the probe permission)
	"forbidden" |
	// "unknown" — initial state before any probe has run
	"unknown"
