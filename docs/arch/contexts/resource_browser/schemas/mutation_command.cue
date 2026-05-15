// DDD role: ValueObject
package resource_browser

// #MutationCommand is a sum type representing every mutation that
// the resource_browser context may dispatch to the Kubernetes API.
//
// Each variant is an immutable value object. Commands are
// constructed in the UI layer (after confirmation), passed to the
// mutation guard policy for evaluation, and — if approved — handed
// to the KubernetesApiPort adapter for execution.
//
// Commands are also serialised into the #MutationAuditEntry before
// the API call is dispatched. Serialisation MUST redact any field
// that might carry credential material (e.g. annotation values
// beginning with "token" or "password" keys).
#MutationCommand:
	#ApplyYAML |
	#ScaleReplicas |
	#RolloutRestart |
	#DeleteResource |
	#LabelPatch |
	#AnnotationPatch

// #ApplyYAML represents a server-side apply (SSA) operation. The
// caller supplies the complete proposed manifest as a YAML string.
// The adapter encodes it as UTF-8, sets
// Content-Type: application/apply-patch+yaml, and issues a PATCH
// request to the resource's REST path.
#ApplyYAML: {
	commandKind!: "ApplyYAML"

	// targetGVK identifies the kind being applied. Must be present in
	// the resource_browser kind catalogue (ADR-0013).
	targetGVK!: #GroupVersionKind

	// namespace is required for namespaced resources; absent for
	// cluster-scoped resources.
	namespace?: string | null

	// name is the resource name declared in the manifest's metadata.
	name!: string

	// manifestYAML is the full proposed manifest as a YAML string.
	// The adapter validates YAML syntax before dispatch. Minimum
	// length 4 characters ("a: b").
	manifestYAML!: =~".+"

	// manifestDigest is the SHA-256 hex digest of the UTF-8 encoded
	// manifestYAML. Computed by the command constructor and verified
	// by the mutation guard policy.
	manifestDigest!: =~"^[0-9a-f]{64}$"

	// fieldManager is the field manager identifier sent in the SSA
	// request. Must equal "com.archanjo.K8sManager".
	fieldManager!: "com.archanjo.K8sManager"

	// forceConflicts controls the ?force=true query parameter.
	// When true the application forces ownership over conflicting
	// fields. Must be explicitly opt-in by the operator; default
	// is false.
	forceConflicts!: bool
}

// #ScaleReplicas represents a targeted replica count update via the
// /scale subresource. The adapter issues a PATCH on the scale
// subresource with a partial Scale object.
#ScaleReplicas: {
	commandKind!: "ScaleReplicas"

	// targetGVK must be one of Deployment, StatefulSet, or ReplicaSet.
	targetGVK!: #GroupVersionKind

	namespace!: string
	name!: string

	// desiredReplicas is the target replica count. Must be >= 0.
	// Setting to 0 is permitted (scales the workload to zero).
	desiredReplicas!: int & >=0
}

// #RolloutRestart injects a
// kubectl.kubernetes.io/restartedAt annotation into
// spec.template.metadata.annotations via a strategic merge patch.
// Supported for Deployment, DaemonSet, and StatefulSet.
#RolloutRestart: {
	commandKind!: "RolloutRestart"

	// targetGVK must be one of Deployment, DaemonSet, StatefulSet.
	targetGVK!: #GroupVersionKind

	namespace!: string
	name!: string

	// restartedAt is the RFC3339 timestamp injected as the annotation
	// value. Constructed at command creation time.
	restartedAt!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
}

// #DeleteResource represents a single-resource delete operation.
// Requires double-confirm per ADR-0012.
#DeleteResource: {
	commandKind!: "DeleteResource"

	targetGVK!: #GroupVersionKind

	// namespace is required for namespaced resources; absent for
	// cluster-scoped resources.
	namespace?: string | null

	name!: string

	// gracePeriodSeconds is the number of seconds the API server
	// should wait before force-killing the resource. nil means the
	// API server default. 0 means immediate deletion.
	gracePeriodSeconds?: int & >=0 | null

	// propagationPolicy controls how owned objects are garbage
	// collected after deletion. "Foreground" waits for all owned
	// objects to be deleted before the owner is removed.
	// "Background" deletes the owner immediately and garbage-collects
	// owned objects asynchronously. "Orphan" removes the owner but
	// leaves owned objects in place.
	propagationPolicy!: "Foreground" | "Background" | "Orphan"
}

// #LabelPatch replaces or adds labels in metadata.labels via a
// strategic merge patch. Existing labels whose keys are not present
// in the patch are preserved.
#LabelPatch: {
	commandKind!: "LabelPatch"

	targetGVK!: #GroupVersionKind
	namespace?: string | null
	name!: string

	// labelsToSet is the map of key→value pairs to add or update.
	// At least one entry is required.
	labelsToSet!: {[string]: string}

	// labelsToRemove is the list of label keys to remove from the
	// resource. Keys not present on the resource are silently ignored.
	labelsToRemove!: [...string]
}

// #AnnotationPatch replaces or adds annotations in
// metadata.annotations via a strategic merge patch. Existing
// annotations whose keys are not present in the patch are preserved.
#AnnotationPatch: {
	commandKind!: "AnnotationPatch"

	targetGVK!: #GroupVersionKind
	namespace?: string | null
	name!: string

	// annotationsToSet is the map of key→value pairs to add or update.
	// At least one entry is required.
	annotationsToSet!: {[string]: string}

	// annotationsToRemove is the list of annotation keys to remove.
	// Keys not present on the resource are silently ignored.
	annotationsToRemove!: [...string]
}
