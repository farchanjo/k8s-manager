// DDD role: ValueObject

package _shared

import "strings"

// #EventEnvelope is the canonical cross-context domain event envelope.
// Every event emitted on the DomainEventBusPort carries exactly one envelope.
// Fields are defined per ADR-0040.
#EventEnvelope: {
	// eventId is a UUIDv7 — time-ordered and globally unique per RFC 9562 §5.7.
	eventId: #UUIDv7

	// eventType is the dot-qualified event type name, e.g. "resource_browser.MutationApplied".
	// Format: "<sourceContext>.<EventName>". Must be non-empty.
	eventType: string & strings.MinRunes(1)

	// sourceContext identifies the emitting bounded context, e.g. "resource_browser".
	sourceContext: string & strings.MinRunes(1)

	// occurredAt is an RFC 3339 timestamp with millisecond precision.
	occurredAt: #RFC3339

	// traceId is an optional OpenTelemetry-compatible trace identifier.
	// Nil when no active distributed trace context exists.
	traceId?: string

	// correlationId is an optional identifier that groups events
	// originating from the same operator action.
	correlationId?: string

	// version is the event schema version. Starts at 1; incremented on
	// breaking payload changes. Consumers must reject versions they do not
	// understand.
	version: int & >=1
}

// ---------------------------------------------------------------------------
// cluster_connectivity events
// ---------------------------------------------------------------------------

// #ClusterSessionOpened is emitted by cluster_connectivity when a cluster
// session is successfully established and the health probe succeeds.
#ClusterSessionOpened: {
	envelope: #EventEnvelope & {
		sourceContext: "cluster_connectivity"
		eventType:     "cluster_connectivity.ClusterSessionOpened"
	}
	payload: {
		clusterId: #ClusterId
		contextId: #ContextId
		openedAt:  #RFC3339
	}
}

// #ClusterSessionClosed is emitted by cluster_connectivity when a cluster
// session is torn down, whether by operator request, context switch, or quit.
#ClusterSessionClosed: {
	envelope: #EventEnvelope & {
		sourceContext: "cluster_connectivity"
		eventType:     "cluster_connectivity.ClusterSessionClosed"
	}
	payload: {
		clusterId: #ClusterId
		closedAt:  #RFC3339
		reason:    "operator-requested" | "cluster-unreachable" | "app-quit" | "context-switch"
	}
}

// #ClusterSessionDegraded is emitted by cluster_connectivity when a health
// probe fails after a session was previously healthy.
#ClusterSessionDegraded: {
	envelope: #EventEnvelope & {
		sourceContext: "cluster_connectivity"
		eventType:     "cluster_connectivity.ClusterSessionDegraded"
	}
	payload: {
		clusterId:   #ClusterId
		degradedAt:  #RFC3339
		reason:      "network-partition" | "api-server-unhealthy" | "creds-expired"
	}
}

// #WatchStreamReconnected is emitted by cluster_connectivity when a Kubernetes
// API watch stream reconnects after a transient disconnection.
// resourceVersionBefore is the RV used in the failed WATCH; resourceVersionAfter
// is the RV captured from the subsequent LIST (per ADR-0036).
#WatchStreamReconnected: {
	envelope: #EventEnvelope & {
		sourceContext: "cluster_connectivity"
		eventType:     "cluster_connectivity.WatchStreamReconnected"
	}
	payload: {
		clusterId:             #ClusterId
		kind:                  string & strings.MinRunes(1)
		resourceVersionBefore: string
		resourceVersionAfter:  string
		attempts:              int & >=1
	}
}

// #WatchStreamDropped is emitted by cluster_connectivity when a watch stream
// drops events due to AsyncStream buffer overflow (bufferingOldest — ADR-0035).
#WatchStreamDropped: {
	envelope: #EventEnvelope & {
		sourceContext: "cluster_connectivity"
		eventType:     "cluster_connectivity.WatchStreamDropped"
	}
	payload: {
		clusterId:    #ClusterId
		kind:         string & strings.MinRunes(1)
		droppedAt:    #RFC3339
		droppedCount: int & >=1
	}
}

// ---------------------------------------------------------------------------
// resource_browser events
// ---------------------------------------------------------------------------

// #MutationApplied is emitted by resource_browser after a mutating Kubernetes
// operation (apply, patch, scale, delete) is confirmed by the API server.
// Consumed by analytics_dashboard, local_persistence, cluster_intelligence,
// and app_shell per ADR-0040.
#MutationApplied: {
	envelope: #EventEnvelope & {
		sourceContext: "resource_browser"
		eventType:     "resource_browser.MutationApplied"
	}
	payload: {
		clusterId:          #ClusterId
		verb:               string & strings.MinRunes(1)
		gvk:                string & strings.MinRunes(1)
		namespace:          string
		name:               string & strings.MinRunes(1)
		// manifestDigest is the SHA-256 hex digest of the applied manifest.
		manifestDigest:     string & =~"^[0-9a-f]{64}$"
		// confirmationToken ties this event to the confirmation dialog nonce
		// per ADR-0012.
		confirmationToken:  string & strings.MinRunes(1)
	}
}

// #MutationFailed is emitted by resource_browser when a mutating operation
// is rejected by the Kubernetes API server.
#MutationFailed: {
	envelope: #EventEnvelope & {
		sourceContext: "resource_browser"
		eventType:     "resource_browser.MutationFailed"
	}
	payload: {
		clusterId:    #ClusterId
		verb:         string & strings.MinRunes(1)
		gvk:          string & strings.MinRunes(1)
		namespace:    string
		name:         string & strings.MinRunes(1)
		errorCode:    int
		errorMessage: string & strings.MinRunes(1)
	}
}

// #DraftSaved is emitted by resource_browser when an editor draft is
// auto-saved or explicitly saved by the operator.
#DraftSaved: {
	envelope: #EventEnvelope & {
		sourceContext: "resource_browser"
		eventType:     "resource_browser.DraftSaved"
	}
	payload: {
		draftId:                  #UUIDv7
		editorSessionId:          #EditorSessionId
		// sensitiveContentRedacted is true when the redaction policy stripped
		// secret values before persisting the draft (ADR-0010).
		sensitiveContentRedacted: bool
	}
}

// #DraftPruned is emitted by resource_browser when a draft is removed,
// either because its TTL expired or the operator explicitly discarded it.
#DraftPruned: {
	envelope: #EventEnvelope & {
		sourceContext: "resource_browser"
		eventType:     "resource_browser.DraftPruned"
	}
	payload: {
		draftId:  #UUIDv7
		prunedAt: #RFC3339
		reason:   "ttl-expired" | "explicit-discard"
	}
}

// ---------------------------------------------------------------------------
// local_persistence events
// ---------------------------------------------------------------------------

// #AuditEntryAppended is emitted by local_persistence when a new audit log
// entry is written to SQLite. The hash-chained previousEntryDigest enables
// tamper detection per ADR-0012.
#AuditEntryAppended: {
	envelope: #EventEnvelope & {
		sourceContext: "local_persistence"
		eventType:     "local_persistence.AuditEntryAppended"
	}
	payload: {
		auditEntryId:        #UUIDv7
		previousEntryDigest: string & =~"^[0-9a-f]{64}$"
	}
}

// ---------------------------------------------------------------------------
// port_forwarding events
// ---------------------------------------------------------------------------

// #PortForwardEstablished is emitted by port_forwarding when a local TCP
// listener successfully tunnels to the target pod via WebSocket.
#PortForwardEstablished: {
	envelope: #EventEnvelope & {
		sourceContext: "port_forwarding"
		eventType:     "port_forwarding.PortForwardEstablished"
	}
	payload: {
		clusterId:   #ClusterId
		namespace:   string & strings.MinRunes(1)
		podName:     string & strings.MinRunes(1)
		localPort:   int & >=1 & <=65535
		remotePort:  int & >=1 & <=65535
	}
}

// #PortForwardClosed is emitted by port_forwarding when a tunnel is torn down.
#PortForwardClosed: {
	envelope: #EventEnvelope & {
		sourceContext: "port_forwarding"
		eventType:     "port_forwarding.PortForwardClosed"
	}
	payload: {
		clusterId: #ClusterId
		localPort: int & >=1 & <=65535
		closedAt:  #RFC3339
		reason:    string & strings.MinRunes(1)
	}
}

// ---------------------------------------------------------------------------
// terminal_session events
// ---------------------------------------------------------------------------

// #TerminalSessionOpened is emitted by terminal_session when a pod exec
// or node debug WebSocket session is successfully established.
#TerminalSessionOpened: {
	envelope: #EventEnvelope & {
		sourceContext: "terminal_session"
		eventType:     "terminal_session.TerminalSessionOpened"
	}
	payload: {
		clusterId: #ClusterId
		sessionId: #UUIDv7
		target:    "pod-exec" | "node-debug"
		namespace: string & strings.MinRunes(1)
		name:      string & strings.MinRunes(1)
	}
}

// #TerminalSessionClosed is emitted by terminal_session when an exec session
// terminates, whether by operator close, process exit, or network error.
#TerminalSessionClosed: {
	envelope: #EventEnvelope & {
		sourceContext: "terminal_session"
		eventType:     "terminal_session.TerminalSessionClosed"
	}
	payload: {
		sessionId: #UUIDv7
		exitCode:  int
		closedAt:  #RFC3339
	}
}

// ---------------------------------------------------------------------------
// helm_management events
// ---------------------------------------------------------------------------

// #HelmRollbackInitiated is emitted by helm_management when a rollback
// command is dispatched to the Kubernetes API (Secrets with owner=helm label).
#HelmRollbackInitiated: {
	envelope: #EventEnvelope & {
		sourceContext: "helm_management"
		eventType:     "helm_management.HelmRollbackInitiated"
	}
	payload: {
		clusterId:    #ClusterId
		releaseName:  string & strings.MinRunes(1)
		fromRevision: int & >=1
		toRevision:   int & >=1
	}
}

// #HelmManifestApplied is emitted by helm_management for each Kubernetes
// resource that the rollback orchestrator applies via Server-Side Apply
// while restoring a target revision. One event per (gvk, namespace, name)
// triple in the rendered manifest set. Consumed by analytics_dashboard,
// local_persistence (audit trail), and app_shell (toast feedback).
//
// Distinct from `resource_browser.MutationApplied` — that event carries an
// operator-supplied confirmationToken from the editor confirmation dialog,
// which does not exist in the helm rollback flow. Modelling helm applies as
// a separate event preserves the `event_bus_policy.rego` sourceContext rule
// (sourceContext must match the eventType prefix).
#HelmManifestApplied: {
	envelope: #EventEnvelope & {
		sourceContext: "helm_management"
		eventType:     "helm_management.HelmManifestApplied"
	}
	payload: {
		clusterId:      #ClusterId
		releaseName:    string & strings.MinRunes(1)
		toRevision:     int & >=1
		gvk:            string & strings.MinRunes(1)
		namespace:      string
		name:           string & strings.MinRunes(1)
		// manifestDigest is the SHA-256 hex digest of the rendered resource
		// manifest at the time it was applied — supports audit-trail tamper
		// detection without storing the manifest itself on the bus.
		manifestDigest: string & =~"^[0-9a-f]{64}$"
	}
}

// #HelmRollbackCompleted is emitted by helm_management when the API server
// confirms (or rejects) a rollback operation.
#HelmRollbackCompleted: {
	envelope: #EventEnvelope & {
		sourceContext: "helm_management"
		eventType:     "helm_management.HelmRollbackCompleted"
	}
	payload: {
		clusterId:   #ClusterId
		releaseName: string & strings.MinRunes(1)
		completedAt: #RFC3339
		status:      "succeeded" | "aborted" | "partial-failure"
	}
}

// ---------------------------------------------------------------------------
// cluster_intelligence events
// ---------------------------------------------------------------------------

// #ToolInvoked is emitted by cluster_intelligence each time the in-process
// MCP server dispatches a tool call on behalf of the assistant.
// Consumed by assistant_chat to echo tool call metadata into the chat UI.
#ToolInvoked: {
	envelope: #EventEnvelope & {
		sourceContext: "cluster_intelligence"
		eventType:     "cluster_intelligence.ToolInvoked"
	}
	payload: {
		sessionId:  #UUIDv7
		toolName:   string & strings.MinRunes(1)
		// args is a JSON-serialized string of the tool argument map.
		args:       string
		durationMs: int & >=0
	}
}

// ---------------------------------------------------------------------------
// app_shell events
// ---------------------------------------------------------------------------

// #DiagnosticsCollected is emitted by app_shell when the diagnostics bundle
// export completes (ADR-0027).
#DiagnosticsCollected: {
	envelope: #EventEnvelope & {
		sourceContext: "app_shell"
		eventType:     "app_shell.DiagnosticsCollected"
	}
	payload: {
		collectedAt:     #RFC3339
		bundleSizeBytes: int & >=0
	}
}

// #LocaleChanged is emitted by app_shell when the operator selects a new
// display locale in settings (ADR-0033).
#LocaleChanged: {
	envelope: #EventEnvelope & {
		sourceContext: "app_shell"
		eventType:     "app_shell.LocaleChanged"
	}
	payload: {
		from: string & strings.MinRunes(2)
		to:   string & strings.MinRunes(2)
	}
}

// #ThemeChanged is emitted by app_shell when the operator changes the
// color theme preference (ADR-0021).
#ThemeChanged: {
	envelope: #EventEnvelope & {
		sourceContext: "app_shell"
		eventType:     "app_shell.ThemeChanged"
	}
	payload: {
		theme: "system" | "light" | "dark"
	}
}

// #PreferencesUpdated is emitted by app_shell when any operator preference
// is persisted. valueDigest is the SHA-256 hex digest of the new value,
// avoiding leaking the raw preference value into the event stream.
#PreferencesUpdated: {
	envelope: #EventEnvelope & {
		sourceContext: "app_shell"
		eventType:     "app_shell.PreferencesUpdated"
	}
	payload: {
		key:         string & strings.MinRunes(1)
		valueDigest: string & =~"^[0-9a-f]{64}$"
	}
}

// #ContextSwitched is emitted by app_shell when the operator selects a
// different kubeconfig context. Consumed by context_navigation and
// cluster_intelligence.
#ContextSwitched: {
	envelope: #EventEnvelope & {
		sourceContext: "app_shell"
		eventType:     "app_shell.ContextSwitched"
	}
	payload: {
		fromContextId: #ContextId
		toContextId:   #ContextId
		switchedAt:    #RFC3339
	}
}

// ---------------------------------------------------------------------------
// assistant_chat events
// ---------------------------------------------------------------------------

// #PromptInjectionSuspected is emitted by assistant_chat when the
// ContentFilterGateway content-filter layer (Layer 3 — ADR-0048) matches a
// denial pattern in a cluster-origin string before it is injected into the
// LLM context. The full payload is never included in the event; only the
// pattern ID, source identity, and a short sanitized excerpt are carried to
// avoid storing adversarial content in the event stream.
#PromptInjectionSuspected: {
	envelope: #EventEnvelope & {
		sourceContext: "assistant_chat"
		eventType:     "assistant_chat.PromptInjectionSuspected"
	}
	payload: {
		sessionId: #UUIDv7
		// patternId is the first denial pattern that matched, e.g. "PI-001".
		patternId:        string & strings.MinRunes(1)
		// source is "<kind>/<name>" of the originating Kubernetes resource.
		source:           string
		// sanitizedExcerpt is the first 64 chars of the sanitized payload.
		sanitizedExcerpt: string & =~"^.{0,64}$"
		// matchedPatterns is the full set of pattern IDs that fired.
		matchedPatterns: [...string]
	}
}

// ---------------------------------------------------------------------------
// DomainEventBusActor meta-events
// ---------------------------------------------------------------------------

// #DomainEventDropped is emitted by DomainEventBusActor to its meta-stream
// when a subscriber's AsyncStream buffer overflows and the oldest envelope
// is discarded. Feeds the self-monitoring diagnostics surface (ADR-0027).
// This event is never published on the main bus — only on the dedicated
// meta-stream to avoid recursive overflow.
#DomainEventDropped: {
	envelope: #EventEnvelope & {
		sourceContext: "domain_event_bus"
		eventType:     "domain_event_bus.DomainEventDropped"
	}
	payload: {
		subscriberId: string & strings.MinRunes(1)
		eventType:    string & strings.MinRunes(1)
		droppedAt:    #RFC3339
	}
}
