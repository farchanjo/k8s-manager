// DDD role: AggregateRoot
package port_forwarding

// #PortForwardSession is the aggregate root for a single port-forward
// tunnel session within K8sManager. A session represents the full
// lifecycle of a WebSocket connection to the Kubernetes portforward
// subresource and the local TCP listener(s) that expose the tunnelled
// port(s) to the operator's local tools.
//
// A session is owned by exactly one PortForwardManagerActor (per ADR-0011).
// The actor is the only writer of this value; UI layers read it via the
// ActivePortForwardsReadModel.
//
// Invariants enforced by the aggregate:
//   - id is a UUIDv7; chronological ordering of sessions is natural.
//   - portMappings is non-empty; at least one port must be forwarded.
//   - openedAtRFC3339 is present only when status is "running", "closing",
//     or "closed".
//   - closedAtRFC3339 is present only when status is "closed" or "error".
//   - #ServiceTarget persists the resolved Pod in resolvedPodName once
//     the endpoint selector lookup completes during session open.
//   - bindAddress defaults to "127.0.0.1"; operators may override to
//     "0.0.0.0" but the UI must warn about network exposure.
#PortForwardSession: {
	// id is a UUIDv7 that uniquely identifies this session.
	// UUIDv7 embeds a millisecond-precision timestamp in the most-significant
	// bits, enabling natural chronological ordering of sessions.
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// kubernetesContextId references the active kubeconfig context under
	// which this session was opened. UUIDv7 assigned by cluster_connectivity.
	kubernetesContextId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// target describes the Kubernetes resource this session is forwarding
	// traffic to. Must be either a #PodTarget (direct Pod reference) or a
	// #ServiceTarget (resolved at session open time to a backing Pod).
	target!: #PodTarget | #ServiceTarget

	// portMappings is the ordered list of port forwards active in this
	// session. Each entry maps to one portIndex in the wire protocol.
	// Must contain at least one mapping. The order of entries matches the
	// order of the "ports" query parameters sent in the WebSocket upgrade
	// request.
	portMappings!: [...#PortMapping] & [_, ...#PortMapping]

	// status is the current lifecycle state of the session.
	// Transitions: opening -> running -> closing -> closed
	//              opening -> error
	//              running -> error
	// See ADR-0014 for the full state machine.
	status!: "opening" | "running" | "closing" | "closed" | "error"

	// createdAtRFC3339 is the ISO 8601 / RFC 3339 timestamp at which the
	// session aggregate was created (before the WebSocket handshake begins).
	createdAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

	// openedAtRFC3339 is the timestamp at which the WebSocket upgrade
	// completed and the local TCP listener was successfully bound (transition
	// to "running"). Absent while status is "opening".
	openedAtRFC3339?: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

	// closedAtRFC3339 is the timestamp at which the session reached "closed"
	// or "error". Absent while status is "opening", "running", or "closing".
	closedAtRFC3339?: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
}

// #PodTarget describes a direct reference to a Kubernetes Pod as the
// tunnel endpoint. The port-forward WebSocket upgrade URL is built
// from namespace and podName directly.
#PodTarget: {
	// namespace is the Kubernetes namespace of the target Pod.
	namespace!: =~"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$"

	// podName is the name of the target Pod. Must be a valid Kubernetes
	// DNS label.
	podName!: =~"^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$"
}

// #ServiceTarget describes a Kubernetes Service as the logical target.
// PortForwardManagerActor resolves the Service to a single backing Pod
// via the endpoint selector at session-open time. The resolved Pod name
// is persisted in resolvedPodName so the aggregate remains self-contained
// after resolution; the WebSocket upgrade uses resolvedPodName.
#ServiceTarget: {
	// namespace is the Kubernetes namespace of the Service.
	namespace!: =~"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$"

	// serviceName is the name of the Kubernetes Service.
	serviceName!: =~"^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$"

	// resolvedPodName is the name of the Pod selected by the Service
	// endpoint selector at session-open time. Populated by
	// PortForwardManagerActor after calling ServiceEndpointReaderPort.
	// Absent until the resolution step completes successfully.
	resolvedPodName?: =~"^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$"
}

// #PortMapping represents a single localPort:remotePort pair within a
// session. The position of a #PortMapping in the portMappings list
// determines its portIndex (0-based) in the wire protocol frame header.
#PortMapping: {
	// localPort is the TCP port bound on the local machine. Must be in
	// the range 1..65535. When the operator specifies 0, the kernel assigns
	// a dynamic port; PortForwardManagerActor replaces the 0 with the
	// assigned port after bind(2) completes.
	localPort!: int & >=1 & <=65535

	// remotePort is the TCP port inside the Pod to forward traffic to.
	// Must be in the range 1..65535.
	remotePort!: int & >=1 & <=65535

	// protocol is the transport-layer protocol for this mapping.
	// Only "tcp" is supported; UDP forwarding is out of scope for K8sManager.
	protocol!: "tcp"

	// bindAddress is the local IP address the TCP listener is bound to.
	// Defaults to "127.0.0.1" (loopback only). The operator may override
	// to "0.0.0.0" to expose the tunnel on all interfaces; the UI must
	// display a network-exposure warning in this case.
	bindAddress: string | *"127.0.0.1"
}
