// DDD role: AggregateRoot
package terminal_session

// #TerminalSession is the aggregate root for a single interactive terminal
// session within K8sManager. It represents either a pod exec session
// (kind == "pod_exec") or a node debug session (kind == "node_debug").
//
// A session is owned by exactly one TerminalSessionActor (per ADR-0011).
// The actor is the only writer of this value; UI layers read it via the
// OpenTerminalsReadModel.
//
// Invariants enforced by the aggregate:
//   - Exactly one WebSocket connection exists per session at any time.
//   - sizeRows and sizeCols are positive integers (terminal must have area).
//   - exitCode is present only when status is "closed" or "error".
//   - lastActivityRFC3339 >= createdAtRFC3339.
//   - targetRef discriminator matches kind: pod_exec => #PodTarget,
//     node_debug => #NodeTarget.
#TerminalSession: {
	// id is a UUIDv7 that uniquely identifies this session.
	// UUIDv7 embeds a millisecond-precision timestamp in the most-significant
	// bits, enabling natural chronological ordering of sessions.
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// kind discriminates between pod exec and node debug sessions.
	kind!: "pod_exec" | "node_debug"

	// kubernetesContextId references the active kubeconfig context under
	// which this session was opened. UUIDv7 assigned by cluster_connectivity.
	kubernetesContextId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// targetRef describes the Kubernetes resource this session is attached to.
	// Must be #PodTarget when kind == "pod_exec".
	// Must be #NodeTarget when kind == "node_debug".
	targetRef!: #PodTarget | #NodeTarget

	// command is the argv list passed to the exec endpoint.
	// For interactive sessions this is typically ["/bin/sh"] or ["/bin/bash"].
	// For one-shot sessions it may be any valid command. Must be non-empty.
	command!: [...string] & [_, ...string]

	// tty indicates whether the remote process was started with a pseudo-
	// terminal allocated. Must be true for interactive sessions that render
	// in the terminal UI; may be false for one-shot command execution.
	tty!: bool

	// stdin indicates whether the stdin stream is forwarded. Must be true
	// when tty is true. May be false for log-only / output-capture sessions.
	stdin!: bool

	// createdAtRFC3339 is the ISO 8601 / RFC 3339 timestamp at which the
	// session aggregate was created (before the WebSocket handshake).
	createdAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

	// lastActivityRFC3339 is updated on every inbound (stdout/stderr) or
	// outbound (stdin) frame. Used by the idle-timeout logic in
	// TerminalSessionActor (default timeout 30 min per ADR-0017).
	lastActivityRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

	// status is the current lifecycle state of the session.
	// Transitions: opening -> open -> closing -> closed
	//              opening -> error
	//              open    -> error
	// See ADR-0017 for the full state machine.
	status!: "opening" | "open" | "closing" | "closed" | "error"

	// exitCode captures the process exit code delivered on channel 3
	// (v5.channel.k8s.io error channel) as {"ExitCode":<int>}.
	// Present only when status is "closed" or "error" and the remote
	// process exited with an explicit code. Absent for connection errors.
	exitCode?: int

	// sizeRows is the current terminal height in character rows.
	// Must be >= 1. Updated on every resize event.
	sizeRows!: int & >=1

	// sizeCols is the current terminal width in character columns.
	// Must be >= 1. Updated on every resize event.
	sizeCols!: int & >=1
}

// #PodTarget describes the Kubernetes Pod and container that a pod_exec
// session is attached to. containerName and ephemeralContainerName are
// mutually exclusive: at most one may be present.
#PodTarget: {
	// namespace is the Kubernetes namespace of the target Pod.
	namespace!: =~"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$"

	// podName is the name of the target Pod.
	podName!: =~"^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$"

	// containerName is the name of the regular container to exec into.
	// When absent, the application defaults to the first container in
	// the Pod spec (matching kubectl exec default behaviour).
	containerName?: string

	// ephemeralContainerName is the name of an ephemeral debug container
	// to exec into. Mutually exclusive with containerName.
	// Used when the operator attaches a kubectl debug --target container.
	ephemeralContainerName?: string
}

// #NodeTarget describes the Kubernetes Node and the ephemeral debug Pod
// created by K8sManager to implement the kubectl debug node equivalent.
// The debug Pod is created by the KubernetesDebugCreatorPort before the
// WebSocket exec session is opened.
#NodeTarget: {
	// nodeName is the name of the target Node.
	nodeName!: string

	// debugImage is the container image used for the ephemeral debug Pod.
	// Defaults to "nicolaka/netshoot:v0.13" per ADR-0017.
	debugImage!: string | *"nicolaka/netshoot:v0.13"

	// debugContainerName is the name assigned to the debug container
	// inside the ephemeral debug Pod. Typically "debugger" or derived
	// from the nodeName.
	debugContainerName!: string
}
