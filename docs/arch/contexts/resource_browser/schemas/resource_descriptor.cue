// DDD role: ValueObject
package resource_browser

// #ResourceDescriptor is an immutable description of a Kubernetes
// resource kind as understood by the resource_browser bounded context.
// It is constructed at startup from the static catalogue defined in
// ADR-0013 and extended at runtime by discovered CRD entries.
//
// A #ResourceDescriptor carries no instance-level data. It describes
// the kind itself: its API coordinates, its scope, and the operations
// that the resource_browser context is permitted to perform on its
// instances.
#ResourceDescriptor: {
	// gvk uniquely identifies the Kubernetes API type.
	gvk!: #GroupVersionKind

	// plural is the lowercase plural name used in API paths (e.g.
	// "pods", "deployments", "customresourcedefinitions"). Required
	// for constructing REST paths when using untyped HTTP calls.
	plural!: =~"^[a-z][a-z0-9]*s?$"

	// namespaced is true when instances of this kind are scoped to a
	// Kubernetes namespace. Cluster-scoped resources (e.g. Namespace,
	// PersistentVolume, ClusterRole) set this to false.
	namespaced!: bool

	// supportedVerbs is the closed set of Kubernetes API verbs that
	// the resource_browser context is permitted to issue for instances
	// of this kind. The set is evaluated against the mutation guard
	// Rego policy at dispatch time. The UI uses this set to compose
	// the toolbar and context menu for the kind.
	supportedVerbs!: [...#SupportedVerb]

	// supportedSubresources lists the subresources that the
	// resource_browser context may access for instances of this kind.
	// An empty list means no subresource access is permitted.
	supportedSubresources!: [...#SupportedSubresource]

	// categories mirrors the Kubernetes API category labels associated
	// with this kind (e.g. ["all"], ["workloads"]). Used for sidebar
	// grouping in the UI. May be empty.
	categories!: [...string]

	// permittedOperations is the closed set of UI-level operation tokens
	// that the resource_browser context permits on instances of this
	// kind. ADR-0061 (per-row action menu) and ADR-0066 (FAB) derive
	// menu item visibility from this field. The
	// `resource_mutation_policy.rego` Rego policy maps
	// `MutationCommand.commandKind` to one of these tokens and rejects
	// any command whose required token is absent here.
	//
	// Operation tokens differ from `supportedVerbs` because they encode
	// UI affordances rather than raw Kubernetes API verbs. For example,
	// `scale` is a UI operation backed by the `scale` subresource plus
	// the `patch` verb; `rollout-restart` is a UI operation backed by
	// `patch` with an annotation bump.
	//
	// Operations enumerated in the closed set (see
	// `#PermittedOperation` below).
	permittedOperations!: [...#PermittedOperation]
}

// #PermittedOperation is the closed set of UI-level operation tokens
// referenced by `resource_mutation_policy.rego`, the per-row action
// menu (ADR-0061), and the floating action button (ADR-0066).
//
// - "list"             — list view rendering; always present.
// - "get"              — single-resource fetch; always present.
// - "watch"            — long-lived watch stream subscription.
// - "edit-yaml"        — Edit YAML row action; opens the integrated
//                        editor (ADR-0030) or the inline docked editor
//                        pane (ADR-0064).
// - "delete"           — Delete row action; requires double-confirm
//                        per ADR-0012.
// - "events"           — View Events row action; surfaces the events
//                        feed for the selected resource.
// - "create"           — Create action; surfaces the FAB
//                        (ADR-0066) and the "Create from scratch"
//                        skeleton template path.
// - "scale"            — Scale row action (Workloads family);
//                        Deployment, StatefulSet, ReplicaSet only.
// - "rollout-restart"  — Rollout Restart row action;
//                        Deployment, StatefulSet, DaemonSet only.
// - "logs"             — View Logs row action; Pod only.
// - "exec"             — Open Terminal row action; Pod only.
#PermittedOperation:
	"list" | "get" | "watch" | "edit-yaml" | "delete" | "events" |
	"create" | "scale" | "rollout-restart" | "logs" | "exec"

// #GroupVersionKind encodes the three-part Kubernetes type identity.
// The group is empty for core/v1 kinds.
#GroupVersionKind: {
	// group is the API group (e.g. "apps", "batch",
	// "networking.k8s.io"). Empty string for the core group (v1).
	group!: string

	// version is the API version string (e.g. "v1", "v1beta1").
	version!: =~"^v[0-9]"

	// kind is the PascalCase Kubernetes kind name (e.g. "Pod",
	// "Deployment", "CustomResourceDefinition").
	kind!: =~"^[A-Z][A-Za-z0-9]+$"
}

// #SupportedVerb is the closed set of Kubernetes API verbs and
// derived UI operations that the resource_browser context may issue.
//
// - "get"    — fetch a single resource manifest from the API server.
// - "list"   — fetch all instances of a kind (optionally filtered by
//              namespace or label selector).
// - "watch"  — open a long-lived watch stream for a kind (or single
//              resource) to receive incremental updates.
// - "create" — create a new instance from a submitted manifest.
// - "update" — replace the full manifest of an existing instance.
// - "patch"  — apply a partial update (server-side apply is the
//              default strategy; see ADR-0012).
// - "delete" — delete a single instance. Requires double-confirm per
//              ADR-0012.
#SupportedVerb: "get" | "list" | "watch" | "create" | "update" | "patch" | "delete"

// #SupportedSubresource is the closed set of Kubernetes subresources
// that the resource_browser context may access.
//
// - "status"      — read or update the .status sub-object.
// - "scale"       — read or update the /scale sub-resource (replica
//                   count). Available for Deployment, StatefulSet,
//                   ReplicaSet.
// - "logs"        — stream container logs via the /log sub-resource.
//                   Available for Pod only.
// - "exec"        — open an interactive shell via the /exec
//                   sub-resource. Reserved for a future release; not
//                   enabled in MVP+.
// - "portforward" — open a port-forward tunnel via the /portforward
//                   sub-resource. Reserved for a future release; not
//                   enabled in MVP+.
#SupportedSubresource: "status" | "scale" | "logs" | "exec" | "portforward"
