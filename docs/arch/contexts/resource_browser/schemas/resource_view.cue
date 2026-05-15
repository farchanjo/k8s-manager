// DDD role: ReadModel
package resource_browser

// #ResourceListItem is a lightweight read model projected from a
// Kubernetes resource manifest for display in the list view. It
// carries enough information to populate a table row and support
// sorting, filtering, and selection, without loading the full
// manifest into memory for every item in the list.
//
// #ResourceListItem is immutable. A new projection is emitted for
// every watch event that affects the corresponding resource.
#ResourceListItem: {
	// id is a UUIDv7 generated deterministically from the
	// (contextId, namespace, kind, name) tuple. Stable across reloads
	// as long as the Kubernetes UID is unchanged.
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// gvk identifies the Kubernetes API type of this resource.
	gvk!: #GroupVersionKind

	// namespace is the Kubernetes namespace of this resource. Absent
	// (null) for cluster-scoped resources such as Namespace,
	// PersistentVolume, and ClusterRole.
	namespace?: string | null

	// name is the Kubernetes resource name within its namespace (or
	// cluster scope). Non-empty.
	name!: =~"^[a-z0-9][-a-z0-9.]*[a-z0-9]$|^[a-z0-9]$"

	// uid is the Kubernetes object UID as assigned by the API server.
	// Used to detect resource re-creation (same name, new UID).
	uid!: string

	// creationTimestamp is the RFC3339 timestamp at which the
	// resource was created on the API server.
	creationTimestamp!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"

	// status is a concise, human-readable status string derived from
	// the resource's .status field. The derivation is kind-specific
	// (e.g. "Running 2/2" for a Pod, "3/3" for a Deployment,
	// "Bound" for a PVC). Empty string when no status is available.
	status!: string

	// ageSeconds is the number of whole seconds elapsed since
	// creationTimestamp. Recomputed on each projection emission.
	ageSeconds!: int & >=0

	// labels is the full set of metadata.labels from the resource.
	// May be empty. Used for label selector filtering in the UI.
	labels!: {[string]: string}

	// annotations is the full set of metadata.annotations from the
	// resource. May be empty. Potentially large for resources managed
	// by Helm or other controllers; the UI truncates values longer
	// than 256 characters in the annotations inspector.
	annotations!: {[string]: string}
}

// #ResourceDetail is the full read model for a single resource
// opened in the detail panel. It carries the original JSON manifest
// as returned by the API server, plus structured projections of the
// most diagnostically useful sub-objects.
//
// #ResourceDetail is immutable. A new projection is emitted when the
// resource is re-fetched or when a watch event carries a full object.
#ResourceDetail: {
	// listItem is the #ResourceListItem projection for this resource,
	// kept in sync with the detail so that the list view can update
	// its row without re-fetching.
	listItem!: #ResourceListItem

	// rawJSON is the full resource manifest as returned by the API
	// server, serialised as a JSON string. The UI renders this in the
	// YAML editor panel after converting to YAML via Yams.
	rawJSON!: string

	// conditions is the parsed .status.conditions array, if present.
	// Empty list when the resource kind does not use conditions or
	// when the current status has no conditions.
	conditions!: [...#StatusCondition]

	// recentEvents is the list of Kubernetes Event objects whose
	// involvedObject.uid matches this resource's uid, ordered by
	// lastTimestamp descending, capped at the most recent 50 events.
	// Empty list when no events are available.
	recentEvents!: [...#EventSummary]
}

// #StatusCondition is a projection of a single entry in a
// Kubernetes .status.conditions array.
#StatusCondition: {
	// conditionType mirrors the .type field (e.g. "Ready",
	// "Available", "Progressing", "PodScheduled").
	conditionType!: string

	// status is "True", "False", or "Unknown".
	status!: "True" | "False" | "Unknown"

	// reason is the short CamelCase reason code from the .reason
	// field. May be empty for older API objects.
	reason!: string

	// message is the human-readable message from the .message field.
	// May be empty.
	message!: string

	// lastTransitionTime is the RFC3339 timestamp of the most recent
	// transition for this condition.
	lastTransitionTime!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
}

// #EventSummary is a lightweight projection of a single Kubernetes
// Event object, used in the recent events list in #ResourceDetail.
#EventSummary: {
	// reason is the short reason string from the Event (e.g.
	// "Scheduled", "Pulled", "Started", "BackOff").
	reason!: string

	// message is the human-readable event message.
	message!: string

	// eventType is the Kubernetes event type: "Normal" or "Warning".
	eventType!: "Normal" | "Warning"

	// count is the number of times this event has occurred.
	count!: int & >=1

	// lastTimestamp is the RFC3339 timestamp of the most recent
	// occurrence of this event.
	lastTimestamp!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
}
