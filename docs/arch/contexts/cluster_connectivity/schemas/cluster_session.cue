// DDD role: AggregateRoot
// DDD Role: AggregateRoot
// Bounded context: cluster_connectivity
// Described by: ADR-0025 (per-cluster isolation strategy)
//
// #ClusterSession is the AggregateRoot for a single active cluster connection.
// Each cluster that the operator opens or pins materialises exactly one
// ClusterSession. Nothing inside this aggregate is accessible from outside
// the ClusterSessionActor that owns it.

package cluster_connectivity

// _uuidV7Pattern matches a canonical UUIDv7 string.
// Format: xxxxxxxx-xxxx-7xxx-[89ab]xxx-xxxxxxxxxxxx
#UUIDv7: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

// #LifecycleState represents the operational state of a cluster session.
// Transitions: connecting → connected → degraded → disconnected → terminating
#LifecycleState: "connecting" | "connected" | "degraded" | "disconnected" | "terminating"

// #RFC3339: a non-empty string expected to conform to RFC 3339.
#RFC3339: string & !=""

// #PoolStats is a snapshot of the HTTPClient connection pool metrics.
// This is captured at a point in time and published as part of
// #PoolStatsSnapshot events. It is a ValueObject — immutable once
// constructed.
#PoolStats: {
	// idleConnections is the number of open but idle TCP connections
	// currently held in the pool awaiting reuse.
	idleConnections: int & >=0

	// activeConnections is the number of connections currently in use
	// by an in-flight HTTP request.
	activeConnections: int & >=0

	// requestsInFlight is the number of HTTP requests currently
	// awaiting a response from the API server.
	requestsInFlight: int & >=0

	// requestsCompleted is the cumulative count of successfully
	// completed HTTP requests since the session was opened.
	requestsCompleted: int & >=0

	// requestsFailed is the cumulative count of HTTP requests that
	// resulted in a transport-level error (excludes HTTP 4xx/5xx).
	requestsFailed: int & >=0
}

// #WatchStreamRef is a lightweight reference to an active Kubernetes
// watch stream registered inside a ClusterSession.
// DDD Role: ValueObject (lives inside the WatchStreamRegistry list).
#WatchStreamRef: {
	// id uniquely identifies this watch stream within the session.
	id: #UUIDv7

	// apiGroup is the Kubernetes API group (e.g. "apps", "" for core).
	apiGroup: string & !=""

	// resourceKind is the Kubernetes resource kind being watched
	// (e.g. "Pod", "Deployment", "ConfigMap").
	resourceKind: string & !=""

	// namespace is the Kubernetes namespace scope for this watch.
	// An empty string indicates a cluster-scoped watch.
	namespace: string

	// openedAt is the RFC 3339 timestamp when the watch stream was
	// established.
	openedAt: #RFC3339

	// status is the current operational status of this stream.
	status: "active" | "reconnecting" | "closed"
}

// #ExecSessionRef is a lightweight reference to an active exec channel
// (kubectl exec or equivalent) registered inside a ClusterSession.
// DDD Role: ValueObject (lives inside the ExecSessionRegistry list).
#ExecSessionRef: {
	// id uniquely identifies this exec session within the cluster session.
	id: #UUIDv7

	// podName is the target Kubernetes pod name.
	podName: string & !=""

	// namespace is the Kubernetes namespace of the target pod.
	namespace: string & !=""

	// containerName is the container within the pod, if specified.
	// Empty string means the default container was used.
	containerName: string

	// openedAt is the RFC 3339 timestamp when the exec channel was
	// established.
	openedAt: #RFC3339

	// status is the current operational status of this exec channel.
	status: "active" | "closing" | "closed"
}

// #PortForwardRef is a lightweight reference to an active port-forward
// listener registered inside a ClusterSession (ADR-0014).
// DDD Role: ValueObject (lives inside the PortForwardRegistry list).
#PortForwardRef: {
	// id uniquely identifies this port-forward within the cluster session.
	id: #UUIDv7

	// targetKind is the Kubernetes workload kind backing this
	// port-forward (e.g. "Pod", "Service", "Deployment").
	targetKind: string & !=""

	// targetName is the name of the target workload.
	targetName: string & !=""

	// namespace is the Kubernetes namespace of the target workload.
	namespace: string & !=""

	// localPort is the local TCP port that the listener is bound to.
	localPort: int & >=1 & <=65535

	// remotePort is the port on the target workload to which
	// connections are forwarded.
	remotePort: int & >=1 & <=65535

	// openedAt is the RFC 3339 timestamp when the listener was
	// established.
	openedAt: #RFC3339

	// status is the current operational status of this port-forward.
	status: "listening" | "closing" | "closed"
}

// #TerminalSessionRef is a lightweight reference to an active terminal
// session registered inside a ClusterSession (ADR-0017).
// DDD Role: ValueObject (lives inside the TerminalSessionRegistry list).
#TerminalSessionRef: {
	// id uniquely identifies this terminal session within the cluster session.
	id: #UUIDv7

	// displayName is a human-readable label for the terminal pane,
	// typically the namespace or workload name used as shell context.
	displayName: string & !=""

	// openedAt is the RFC 3339 timestamp when the terminal session
	// was opened.
	openedAt: #RFC3339

	// status is the current operational status of this terminal session.
	status: "active" | "closing" | "closed"
}

// #ViewState captures the per-cluster UI state that must survive a
// cluster switch and be restored on cold launch (ADR-0025, ADR-0026).
// Persisted atomically to
// ~/.config/k8smanager/clusters/<clusterId>/view_state.json.
// DDD Role: ValueObject (lives inside ClusterSession).
#ViewState: {
	// sidebarExpanded indicates whether the left sidebar is expanded
	// for this cluster.
	sidebarExpanded: bool | *true

	// contentScrollPosition is the normalised (0.0–1.0) vertical scroll
	// position of the main content area for this cluster.
	contentScrollPosition: float64 & >=0.0 & <=1.0 | *0.0

	// selectedDetailTab is the identifier of the currently selected
	// tab in the detail panel (e.g. "overview", "yaml", "events",
	// "logs").
	selectedDetailTab: string | *"overview"

	// namespaceFilter is the namespace selector string currently
	// applied in the resource browser for this cluster.
	// Empty string means all namespaces.
	namespaceFilter: string | *""

	// searchQuery is the current text in the search bar for this
	// cluster. Empty string means no active search.
	searchQuery: string | *""
}

// #ClusterSession is the AggregateRoot for one cluster connection.
// The aggregate is owned by exactly one ClusterSessionActor (Swift actor).
// All mutations go through that actor. Nothing is accessible from outside
// the actor boundary.
//
// DDD Role: AggregateRoot
// Owner: ClusterSessionActor (cluster_connectivity infrastructure)
// Persistence boundary: ~/.config/k8smanager/clusters/<clusterId>/
#ClusterSession: {
	// id is the UUIDv7 identifier for this session instance.
	// A new UUIDv7 is generated each time a session is opened, even
	// for a cluster that was previously open.
	id: #UUIDv7

	// clusterId is the shared-kernel UUIDv7 that identifies the
	// Kubernetes cluster this session is connected to.
	clusterId: #UUIDv7

	// kubernetesContextId is the UUIDv7 of the kubeconfig context
	// entry that was active when this session was opened. Allows
	// detection of context drift during a session.
	kubernetesContextId: #UUIDv7

	// lifecycleState is the current operational state of this session.
	lifecycleState: #LifecycleState

	// openedAt is the RFC 3339 timestamp when this session was
	// created (i.e. when ClusterSessionActor was spawned).
	openedAt: #RFC3339

	// lastUsedAt is the RFC 3339 timestamp of the most recent
	// HTTP request or user interaction attributed to this session.
	// Used by the idle-pool reaping and aggressive-shutdown logic.
	lastUsedAt: #RFC3339

	// idleTimeoutMinutes controls the aggressive-shutdown threshold.
	// 0 means the session never shuts down automatically due to
	// idleness (individual HTTP connections are still reaped by the
	// pool's idleTimeout). Positive values trigger a full teardown
	// after N consecutive minutes of inactivity.
	idleTimeoutMinutes: int & >=0 | *0

	// httpPoolStats is a point-in-time snapshot of the HTTPClient
	// connection pool metrics for this session. Updated every 30 s
	// and on every request completion.
	httpPoolStats: #PoolStats

	// watchStreamRegistry is the list of all active Kubernetes watch
	// streams currently managed by this session.
	watchStreamRegistry: [...#WatchStreamRef]

	// execSessionRegistry is the list of all active exec channels
	// currently managed by this session.
	execSessionRegistry: [...#ExecSessionRef]

	// portForwardRegistry is the list of all active port-forward
	// listeners currently managed by this session.
	portForwardRegistry: [...#PortForwardRef]

	// terminalSessionRegistry is the list of all active terminal
	// sessions currently managed by this session.
	terminalSessionRegistry: [...#TerminalSessionRef]

	// viewState is the per-cluster UI state snapshot. Persisted
	// within 5 seconds of any mutation via debounced atomic write.
	viewState: #ViewState
}
