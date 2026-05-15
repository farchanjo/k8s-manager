// DDD role: DomainService
package resource_browser

// resource_browser_service.cue — Domain services that orchestrate the full
// lifecycle of an operator-initiated mutation within the resource_browser
// bounded context.
//
// Three services are declared here:
//
//   #ResourceBrowserService  — entry point; coordinates command building,
//                              gate evaluation, dispatch, and audit writing.
//   #MutationCommandFactory  — constructs a typed #MutationCommand from raw
//                              UI input; applies redaction rules so that
//                              credential material never reaches the audit log.
//   #MutationDispatchService — executes a verified command by sequencing the
//                              policy gate, the audit-log write, and the
//                              Kubernetes server-side-apply (SSA) call.
//
// Invariants enforced here are complementary to those in the #MutationCommand
// and #MutationAuditEntry value objects.

// UUIDv7 pattern used across all identity fields in this context.
#_UUIDv7: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

// #MutationOutcome captures what happened after a command was dispatched.
// It is a transient return value, not persisted directly; the persisted form
// lives in #MutationAuditEntry (cluster_mutation_audit table).
#MutationOutcome: {
	// auditEntryId links this outcome back to the persisted audit row.
	auditEntryId!: #_UUIDv7

	// status mirrors the outcome column of cluster_mutation_audit.
	status!: "succeeded" | "denied_by_policy" | "failed" | "cancelled"

	// kubernetesStatusCode is populated for any outcome that reached
	// the Kubernetes API server; absent for "denied_by_policy" or
	// "cancelled" outcomes that were stopped before the API call.
	kubernetesStatusCode?: int & >=100 & <=599

	// detail is an operator-visible reason string. MUST NOT contain
	// credential material (tokens, certificates, bearer values).
	detail?: string
}

// #ResourceBrowserService is the primary domain service (entry point) exposed
// to the UI layer. It accepts a fully constructed #MutationCommand and a
// Confirmation value, orchestrates the supporting services, and returns a
// #MutationOutcome.
//
// Conceptual method signature (not executable CUE — for design documentation):
//
//   func execute(cmd: #MutationCommand, confirmation: #Confirmation) -> #MutationOutcome
//
// Execution sequence enforced by this service:
//   1. Delegate to #MutationCommandFactory to validate and enrich the command.
//   2. Delegate to #MutationDispatchService for gate + audit + SSA call.
//   3. Return the #MutationOutcome (succeeded, denied, failed, or cancelled).
#ResourceBrowserService: {
	// id uniquely identifies this service instance within the application
	// process. Useful for tracing and log correlation.
	id!: #_UUIDv7

	// kubernetesContextId identifies the cluster context this service
	// instance is scoped to. Derived from the active ClusterReadModel
	// provided by the cluster_connectivity bounded context.
	kubernetesContextId!: #_UUIDv7

	// activeFieldManager is the server-side-apply field manager string
	// sent in every PATCH/apply request. Defaults to the application's
	// canonical field manager name.
	activeFieldManager: string | *"com.archanjo.K8sManager"
}

// #MutationCommandFactory is a secondary domain service responsible for
// constructing a well-formed #MutationCommand from raw UI input (form data,
// selected resource, chosen verb). It performs three duties:
//
//   a) Input validation — rejects unknown GVK kinds, missing names, etc.
//   b) Redaction — strips credential material from annotation values, label
//      values, and Secret data fields before the command is serialised.
//   c) Digest computation — for #ApplyYAML commands, computes the sha256
//      manifest digest that will be stored in the audit entry.
//
// The factory output is a sealed #MutationCommand ready for dispatch; it
// does NOT interact with the Kubernetes API or the SQLite store.
#MutationCommandFactory: {
	// id uniquely identifies this factory instance (for tracing).
	id!: #_UUIDv7

	// kubernetesContextId is propagated into every command produced by
	// this factory, ensuring commands are always context-scoped.
	kubernetesContextId!: #_UUIDv7

	// sensitiveAnnotationKeys is the deny-list of annotation key suffixes
	// whose values are redacted to "<redacted>" before command serialisation.
	// Callers may extend this list at service construction time.
	sensitiveAnnotationKeys: [...string] | *[
		"kubectl.kubernetes.io/last-applied-configuration",
		"token",
		"password",
		"secret",
	]
}

// #MutationDispatchService is a secondary domain service that coordinates the
// three sequential side-effecting operations required to safely mutate a
// Kubernetes resource:
//
//   Step 1 — Policy gate: evaluate the mutation guard rules. If the command
//             is denied, write a "denied_by_policy" audit row and return
//             immediately without making an API call.
//   Step 2 — Audit write (before API call): persist a #MutationAuditEntry
//             with outcome=null (in-flight) to the cluster_mutation_audit
//             table via the ClusterMutationAuditPort.
//   Step 3 — SSA call: invoke the Kubernetes API via the KubernetesPort.
//             Update the audit row with the final outcome and completedAt.
//
// Designing the audit write BEFORE the API call (Step 2 before Step 3) is
// intentional: it ensures that a network timeout or crash cannot produce an
// unaudited mutation.
#MutationDispatchService: {
	// id uniquely identifies this dispatcher instance (for tracing).
	id!: #_UUIDv7

	// kubernetesContextId scopes all dispatch operations to one cluster.
	kubernetesContextId!: #_UUIDv7

	// fieldManagerId is passed as the field manager string in SSA PATCH
	// requests. Should match #ResourceBrowserService.activeFieldManager.
	fieldManagerId: string | *"com.archanjo.K8sManager"

	// maxConfirmationTokenAgeSeconds is the maximum age of a confirmation
	// token that will be accepted by this dispatcher. Tokens older than
	// this limit are treated as expired, and the command is denied.
	maxConfirmationTokenAgeSeconds: int & >0 | *300
}
