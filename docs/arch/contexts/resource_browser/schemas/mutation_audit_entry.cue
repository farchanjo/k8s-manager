// DDD role: ValueObject
package resource_browser

// #MutationAuditEntry is the immutable record of a single mutation
// attempt. It is written to the cluster_mutation_audit SQLite table
// (owned by local_persistence) before the Kubernetes API call is
// dispatched. Rows are never updated or deleted by the application.
//
// The entry serves three purposes:
//   1. Forensic review — an operator can query the table to
//      reconstruct the history of changes made to a cluster.
//   2. Confirmation linkage — the confirmationToken ties the
//      persisted record to the specific operator gesture (modal
//      confirmation) that authorised the mutation.
//   3. Integrity verification — the manifestDigest allows post-hoc
//      verification that the YAML sent to the cluster matches the
//      YAML that was previewed in the diff modal.
//
// SECURITY INVARIANT: #MutationAuditEntry MUST NOT contain
// credential material. Kubernetes API tokens, client certificates,
// kubeconfig bearer tokens, exec-plugin output, and Secret manifest
// values MUST NOT appear in any field of this type. The command
// serialiser is responsible for redacting sensitive annotation and
// label values before the command is embedded in this entry.
#MutationAuditEntry: {
	// id is a UUIDv7 generated at command construction time. Unique
	// across all audit entries in the table.
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// requestedAt is the RFC3339 timestamp at which the command was
	// constructed and the audit entry was first written. This is the
	// time the operator initiated the action in the UI, before the
	// confirmation modal was shown.
	requestedAt!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"

	// completedAt is the RFC3339 timestamp at which the mutation
	// outcome was determined (API response received, or operator
	// cancelled). Absent until the outcome is known.
	completedAt?: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" | null

	// kubernetesContextId is the UUIDv7 of the active cluster context
	// at the time the mutation was requested. Derived from the
	// ClusterReadModel provided by cluster_connectivity.
	kubernetesContextId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// command is the serialised #MutationCommand that was submitted.
	// The commandKind discriminant field allows the reader to
	// reconstruct the original command variant. Sensitive annotation
	// and label values are redacted before serialisation.
	command!: #MutationCommand

	// outcome records the final status of this mutation attempt.
	//
	// - "succeeded"  — the Kubernetes API returned a success status
	//                  code (2xx) and the mutation was applied.
	// - "denied"     — the mutation guard policy denied the command
	//                  before any API call was made.
	// - "failed"     — the Kubernetes API returned an error status
	//                  code, or a network error occurred.
	// - "cancelled"  — the operator dismissed the confirmation modal
	//                  or pressed Cancel before the API call was
	//                  dispatched.
	outcome!: "succeeded" | "denied" | "failed" | "cancelled"

	// kubernetesStatusCode is the HTTP status code returned by the
	// Kubernetes API server for the mutation request. Absent when no
	// API call was made (outcome is "denied" or "cancelled").
	kubernetesStatusCode?: int & >=100 & <=599 | null

	// manifestDigest is the SHA-256 hex digest of the UTF-8 encoded
	// YAML manifest sent in the request body. Present only for
	// #ApplyYAML commands; absent for all other command kinds.
	manifestDigest?: =~"^[0-9a-f]{64}$" | null

	// confirmationToken is the UUIDv7 generated at the moment the
	// confirmation modal was displayed to the operator. Its presence
	// in the audit entry proves that the confirmation step was
	// reached. The mutation guard policy verifies that the token is
	// at most 5 minutes old at dispatch time.
	confirmationToken!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// previousEntryDigest is the HMAC-SHA256 hex digest produced as:
	//   HMAC-SHA256(key, prevDigestHex || canonicalEntryJSON_utf8)
	// where `key` is the 256-bit secret stored in the macOS Keychain
	// under service "com.archanjo.K8sManager.audit", account
	// "chain-mac-key-v1" (per ADR-0047). The first (genesis) row
	// stores the sentinel value of 64 zero hex characters. Together
	// the chain forms a key-gated tamper-evident linked list: an
	// adversary with only filesystem write access cannot silently
	// recompute the chain because they lack the Keychain key.
	//
	// The chain is verified by the `spec validate --lane audit`
	// command, which walks all rows in requestedAt order.
	// (See ADR-0047 — supersedes the plain SHA-256 design noted in
	// ADR-0012 MEDIUM-01.)
	previousEntryDigest!: =~"^[0-9a-f]{64}$"

	// keyVersion identifies the Keychain key generation used to
	// produce this entry's previousEntryDigest HMAC tag. Allows the
	// ChainVerifier to select the correct Keychain item in the event
	// that a future key rotation is implemented. Default is "v1",
	// corresponding to the Keychain account "chain-mac-key-v1".
	keyVersion: string & =~"^v[0-9]+$" | *"v1"
}
