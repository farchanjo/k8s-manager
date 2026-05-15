// DDD role: ValueObject
package terminal_session

// #NodeDebugDescriptor is an immutable value object created by the
// TerminalSession aggregate when a node_debug session is initiated.
// It records all parameters of the ephemeral debug Pod that the
// KubernetesDebugCreatorPort will create before the exec WebSocket
// is opened.
//
// Motivation: the debug Pod lifecycle is separate from the WebSocket
// session lifecycle. The descriptor gives the aggregate a complete,
// self-contained record of the Pod to delete at session close (and
// at expiresAtRFC3339 for crash-recovery cleanup).
//
// The Pod created from this descriptor is equivalent to the Pod
// produced by:
//   kubectl debug node/<nodeName> \
//     --image=<debugImage> \
//     --namespace=<namespace> \
//     -it
//
// Invariants:
//   - ephemeralPodName follows the pattern "node-debugger-<nodeName>-<short-uuid>"
//     where short-uuid is the first 8 hex characters of a UUIDv7.
//   - hostNetwork and hostPID are always true (required for node-level
//     debug access).
//   - privileged is true in the initial implementation; a future ADR
//     may introduce configurable security context profiles.
//   - expiresAtRFC3339 is always createdAt + sessionDuration + 60s grace.
//   - The descriptor is immutable after creation; updates are not permitted.
#NodeDebugDescriptor: {
	// nodeName is the Kubernetes node this descriptor targets.
	nodeName!: string

	// ephemeralPodName is the generated name for the debug Pod.
	// Pattern: "node-debugger-<nodeName>-<short-uuid>" where short-uuid
	// is 8 lowercase hex characters derived from a UUIDv7.
	ephemeralPodName!: =~"^node-debugger-.+-[0-9a-f]{8}$"

	// namespace is the Kubernetes namespace in which the debug Pod is
	// created. Defaults to "default". Configurable via user settings.
	namespace!: string | *"default"

	// debugImage is the container image for the debug container.
	// Default: "nicolaka/netshoot:v0.13" per ADR-0017.
	debugImage!: string | *"nicolaka/netshoot:v0.13"

	// hostNetwork indicates whether the debug Pod shares the node's
	// network namespace. Always true for node-level debugging.
	hostNetwork!: true

	// hostPID indicates whether the debug Pod shares the node's PID
	// namespace. Always true for node-level debugging.
	hostPID!: true

	// securityContext captures the security-relevant fields of the
	// debug container's SecurityContext.
	securityContext!: #DebugSecurityContext

	// expiresAtRFC3339 is the timestamp after which the debug Pod should
	// be deleted even if the parent session record is missing. This is
	// the session close time plus a 60-second grace period. The
	// KubernetesDebugCreatorPort schedules a background deletion task
	// at this timestamp as a safety net against application crashes.
	expiresAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
}

// #DebugSecurityContext captures the security fields applied to the
// debug container's pod spec.
//
// Risk note (ADR-0017): privileged: true grants the debug container
// full access to the host kernel. This is required for tools like
// tcpdump, nsenter, strace, and most node-level debugging workflows.
// A future ADR may introduce a non-privileged profile or per-node
// policy enforcement. Operators must be aware that creating a debug
// Pod via this descriptor is a high-privilege operation.
#DebugSecurityContext: {
	// privileged indicates whether the debug container runs in privileged
	// mode. Always true in the current implementation. See ADR-0017 risk
	// section for discussion of this constraint.
	privileged!: bool | *true
}
