// DDD role: ValueObject
package cluster_intelligence

import (
	"time"
)

// #MCPInvocation is the immutable record of one tool execution.
// It is the audit-log entry for the MCP server and is persisted by
// local_persistence for diagnostics.
#MCPInvocation: {
	id!:                 =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
	toolName!:           =~"^[a-z][a-z0-9_]{0,63}$"
	requestedAtRFC3339!: time.Format(time.RFC3339)
	completedAtRFC3339?: time.Format(time.RFC3339)

	// kubernetesContextId is the resolved ContextId from the
	// shared kernel. Required for every invocation; the host
	// supplies the pinned context when the tool does not name
	// one explicitly.
	kubernetesContextId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// argumentsJSON is the validated input. The MCP server records
	// the validated form, not the raw model output.
	argumentsJSON!: string

	outcome!: #MCPOutcome
}

#MCPOutcome:
	#OutcomeSucceeded |
	#OutcomeDeniedByPolicy |
	#OutcomeFailed |
	#OutcomeCancelled

#OutcomeSucceeded: {
	kind!: "succeeded"
	// resultJSON is the UTF-8 JSON body returned to the host.
	resultJSON!: string
	// resultBytes is the size of resultJSON before any truncation.
	resultBytes!: int & >=0
	// truncated is true when resultJSON ends with the truncation
	// marker because the upstream payload exceeded outputMaxBytes.
	truncated!: bool
	// kubernetesStatusCode is the HTTP status code reported by the
	// API server, captured for observability.
	kubernetesStatusCode!: int & >=200 & <300
}

#OutcomeDeniedByPolicy: {
	kind!: "denied_by_policy"
	// rule references the deny-rule identifier in the policy file
	// (e.g., "mutating_verb_forbidden", "tool_not_registered",
	// "resource_not_allowed").
	rule!:   =~"^[a-z][a-z0-9_]{0,63}$"
	detail!: string
}

#OutcomeFailed: {
	kind!: "failed"
	// kubernetesStatusCode is present only when the API server
	// responded with a non-2xx status.
	kubernetesStatusCode?: int & >=400 & <600
	// reason is operator-facing and MUST NOT contain credential
	// material or token fingerprints.
	reason!: string
}

#OutcomeCancelled: {
	kind!: "cancelled"
}
