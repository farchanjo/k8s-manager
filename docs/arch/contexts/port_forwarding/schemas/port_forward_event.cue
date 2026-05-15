// DDD role: ValueObject
package port_forwarding

// #PortForwardEvent is the discriminated union of all domain events
// emitted by PortForwardManagerActor during the lifecycle of a
// PortForwardSession. Events are immutable value objects; they are
// published via AsyncStream to the UI and optionally to the
// ActivePortForwardsReadModel projection.
//
// Invariants:
//   - Every event variant carries a sessionId that references the
//     owning PortForwardSession aggregate.
//   - Events are ordered by occurredAtRFC3339 within a session.
//   - #SessionFailed must never include credential material, raw
//     certificate bytes, or bearer token values in errorCode or detail.
//   - #BytesTransferred is emitted at most once every 5 seconds per
//     session (aggregated counter, not per-frame).
#PortForwardEvent:
	#SessionOpened |
	#SessionFailed |
	#ListenerBound |
	#ListenerClosed |
	#ConnectionAccepted |
	#BytesTransferred |
	#SessionClosed

// #SessionOpened is emitted when the WebSocket upgrade handshake
// completes successfully and the session transitions from "opening"
// to "running". It confirms that the Kubernetes API server accepted the
// portforward.k8s.io subprotocol and that the session is ready to accept
// local TCP client connections.
#SessionOpened: {
	// eventType discriminates this variant.
	eventType!: "session_opened"

	// sessionId references the owning PortForwardSession aggregate.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// occurredAtRFC3339 is the RFC 3339 timestamp when the event was
	// produced by PortForwardManagerActor.
	occurredAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
}

// #SessionFailed is emitted when the session transitions to "error"
// from either "opening" or "running". The error detail must never
// contain credential material (tokens, certificates, passwords).
#SessionFailed: {
	// eventType discriminates this variant.
	eventType!: "session_failed"

	// sessionId references the owning PortForwardSession aggregate.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// occurredAtRFC3339 is the RFC 3339 timestamp when the event was produced.
	occurredAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

	// errorCode is a machine-readable failure category. Examples:
	// "websocket_upgrade_rejected", "pod_not_found", "port_not_exposed",
	// "local_bind_failed", "websocket_closed_abnormally".
	errorCode!: string

	// detail is a human-readable explanation of the failure. Must not
	// include credential material (tokens, certificates, kubeconfig secrets).
	detail!: string
}

// #ListenerBound is emitted once per #PortMapping when the local TCP
// server socket is successfully bound and starts listening. It carries
// the effective localPort (which may differ from the requested port when
// the operator requested dynamic assignment via port 0).
#ListenerBound: {
	// eventType discriminates this variant.
	eventType!: "listener_bound"

	// sessionId references the owning PortForwardSession aggregate.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// occurredAtRFC3339 is the RFC 3339 timestamp when the event was produced.
	occurredAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

	// portIndex is the 0-based index of this mapping in the session's
	// portMappings list, matching the portIndex byte in the wire protocol.
	portIndex!: int & >=0 & <=255

	// effectiveLocalPort is the port the kernel bound after listen(2).
	// When the operator requested dynamic assignment (localPort == 0 in the
	// mapping), this field holds the kernel-assigned ephemeral port.
	effectiveLocalPort!: int & >=1 & <=65535

	// bindAddress is the address the listener is bound to.
	bindAddress!: string

	// isNetworkExposed is true when bindAddress is not "127.0.0.1",
	// indicating the listener is accessible beyond the loopback interface.
	isNetworkExposed!: bool
}

// #ListenerClosed is emitted once per #PortMapping when the local TCP
// server socket is closed during session shutdown (closing -> closed
// transition) or after a session failure.
#ListenerClosed: {
	// eventType discriminates this variant.
	eventType!: "listener_closed"

	// sessionId references the owning PortForwardSession aggregate.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// occurredAtRFC3339 is the RFC 3339 timestamp when the event was produced.
	occurredAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

	// portIndex is the 0-based index of the mapping whose listener was closed.
	portIndex!: int & >=0 & <=255
}

// #ConnectionAccepted is emitted each time a local TCP client connects
// to one of the session's bound listeners. It records the client address
// and port for observability purposes. No payload data is included.
#ConnectionAccepted: {
	// eventType discriminates this variant.
	eventType!: "connection_accepted"

	// sessionId references the owning PortForwardSession aggregate.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// occurredAtRFC3339 is the RFC 3339 timestamp when the event was produced.
	occurredAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

	// portIndex is the 0-based index of the mapping the client connected to.
	portIndex!: int & >=0 & <=255

	// clientAddress is the IP address of the local TCP client (typically
	// "127.0.0.1" for loopback-bound sessions or a LAN address otherwise).
	clientAddress!: string

	// clientPort is the ephemeral source port assigned to the TCP client
	// connection by the kernel.
	clientPort!: int & >=1 & <=65535
}

// #BytesTransferred is emitted at most once every 5 seconds per session
// as an aggregated byte-count snapshot. It reports total bytes flowing
// in both directions since the last emission. No payload content is
// included; only aggregate counts are surfaced for observability.
#BytesTransferred: {
	// eventType discriminates this variant.
	eventType!: "bytes_transferred"

	// sessionId references the owning PortForwardSession aggregate.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// occurredAtRFC3339 is the RFC 3339 timestamp when the event was produced.
	occurredAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

	// bytesIn is the cumulative count of bytes received from the Kubernetes
	// API server (remote → local direction) since the last emission.
	bytesIn!: int & >=0

	// bytesOut is the cumulative count of bytes sent to the Kubernetes
	// API server (local → remote direction) since the last emission.
	bytesOut!: int & >=0
}

// #SessionClosed is emitted when the session transitions to "closed"
// after a cooperative shutdown. The local TCP listener and WebSocket
// connection are both closed at this point.
#SessionClosed: {
	// eventType discriminates this variant.
	eventType!: "session_closed"

	// sessionId references the owning PortForwardSession aggregate.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// occurredAtRFC3339 is the RFC 3339 timestamp when the event was produced.
	occurredAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
}
