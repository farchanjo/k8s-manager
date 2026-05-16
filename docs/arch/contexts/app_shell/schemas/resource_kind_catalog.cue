// DDD role: ValueObject
// ADR: ADR-0050 — Resource navigation taxonomy: 51 standard Kubernetes kinds, CRD discovery,
//                  and multi-document tab system
//      ADR-0013 — Resource browser scope and supported kinds (extended)
//
// Defines #ResourceKindDescriptor, #SidebarCategory, and #ResourceKindCatalog.
//
// The ResourceDescriptorRegistry in resource_browser owns a runtime instance of
// #ResourceKindCatalog. The 51 standard kinds are registered at compile time;
// dynamically-discovered CRD kinds are registered at runtime after CRD discovery.
//
// This schema does NOT include the full CUE enumeration of all 51 standard kinds;
// that enumeration is in resource_descriptor.cue (resource_browser context).
// This schema focuses on the sidebar category taxonomy and the catalog aggregate.

package app_shell

import "strings"

// ---------------------------------------------------------------------------
// #SidebarCategory — enum of sidebar tree section headers
// ---------------------------------------------------------------------------

// #SidebarCategory is the 8-category taxonomy for the resource navigation
// sidebar tree as specified in ADR-0050.
#SidebarCategory:
	"overview" |         // Synthetic ClusterOverview
	"nodes" |            // Node
	"workloads" |        // Deployment, DaemonSet, StatefulSet, ReplicaSet, Pod, Job, CronJob, HPA, VPA
	"config" |           // ConfigMap, Secret, ServiceAccount, PVC, ResourceQuota, LimitRange,
	                     //   PDB, HPA (alias), PriorityClass, RuntimeClass,
	                     //   MutatingWebhookConfiguration, ValidatingWebhookConfiguration
	"network" |          // Service, Endpoints, Ingress, IngressClass, NetworkPolicy,
	                     //   EndpointSlice, HTTPRoute (optional), GatewayClass (opt), Gateway (opt)
	"storage" |          // PersistentVolume, PVC (alias), StorageClass, VolumeAttachment,
	                     //   CSINode, CSIDriver
	"namespaces" |       // Namespace
	"events" |           // Event (merged core/v1 + events.k8s.io/v1)
	"helm" |             // Helm release list (not a Kubernetes resource)
	"access-control" |   // Role, RoleBinding, ClusterRole, ClusterRoleBinding,
	                     //   ServiceAccount (alias), TokenRequest (virtual)
	"custom-resources"   // Dynamic CRD groups, grouped by API group + CRD Catalog meta-entry

// ---------------------------------------------------------------------------
// #PermittedVerb — closed set of UI operation verbs per kind
// ---------------------------------------------------------------------------

// #PermittedVerb is the closed set of operations the UI exposes per kind.
// Matches the operation surface defined in ADR-0013 and extended in ADR-0050.
#PermittedVerb:
	"list" |
	"get" |
	"watch" |
	"edit-yaml" |
	"delete" |
	"scale" |
	"rollout-restart" |
	"logs" |
	"events"

// ---------------------------------------------------------------------------
// #ResourceKindDescriptor — ValueObject
// ---------------------------------------------------------------------------

// #ResourceKindDescriptor describes one Kubernetes resource kind as registered
// in the ResourceDescriptorRegistry. For standard kinds this is populated at
// compile time; for CRD kinds it is populated at runtime via CRD discovery.
#ResourceKindDescriptor: {
	// kindName is the Kubernetes Kind string (PascalCase), e.g. "Deployment".
	kindName: string & strings.MinRunes(1) & =~"^[A-Z][a-zA-Z0-9]*$"

	// apiGroup is the Kubernetes API group, e.g. "apps", "batch", "".
	// Empty string for core/v1 kinds.
	apiGroup: string

	// apiVersion is the preferred version string, e.g. "v1", "apps/v1".
	apiVersion: string & strings.MinRunes(1)

	// resourceName is the plural lowercase resource name used in API paths,
	// e.g. "deployments", "pods", "configmaps".
	resourceName: string & strings.MinRunes(1) & =~"^[a-z][a-z0-9]*$"

	// namespaced indicates whether the resource is namespace-scoped (true) or
	// cluster-scoped (false).
	namespaced: bool

	// primaryCategory is the sidebar category under which this kind appears
	// as its canonical entry.
	primaryCategory: #SidebarCategory

	// aliasCategories lists additional sidebar categories where this kind
	// appears as an alias entry. Alias entries share the same
	// #ResourceKindDescriptor and do not create duplicate watch streams.
	aliasCategories: [...#SidebarCategory]
	aliasCategories: *[] | _

	// permittedVerbs is the closed set of UI operations permitted for this kind.
	// Defined per ADR-0013 and ADR-0050.
	permittedVerbs: [#PermittedVerb, ...]

	// isDynamic is true for kinds discovered at runtime via CRD enumeration.
	// Always false for the 51 standard compile-time kinds.
	isDynamic: bool
	isDynamic: *false | _

	// crdGroup is the API group for dynamic CRD kinds, e.g. "argoproj.io".
	// Absent for standard kinds.
	crdGroup?: string & strings.MinRunes(1)

	// statusFieldPaths is an ordered list of JSON paths tried when extracting
	// the status column value in the generic list view (ADR-0052).
	// The first non-null, non-empty value wins.
	// Standard paths: ".status.phase", ".status.state", ".status.ready", "."
	// Absent for standard kinds that have kind-specific list renderers.
	statusFieldPaths?: [...string & strings.MinRunes(1)]

	// crdOpenAPISchema is the raw JSON-serialised OpenAPI v3 schema extracted
	// from spec.versions[preferredVersion].schema.openAPIV3Schema at discovery time.
	// Absent when no schema is embedded or when x-kubernetes-preserve-unknown-fields
	// is set at root. Only populated for dynamic CRD kinds (isDynamic == true).
	crdOpenAPISchema?: string

	// additionalPrinterColumns mirrors the CRD's spec.additionalPrinterColumns array.
	// Each entry carries a name, jsonPath, and optional type. Used to extend the
	// generic list view with CRD-specific columns.
	additionalPrinterColumns?: [...#PrinterColumn]

	// scaleSubresourceEnabled is true when the CRD declares spec.subresources.scale,
	// enabling the "scale" operation in the action toolbar for CRD instances.
	scaleSubresourceEnabled: bool
	scaleSubresourceEnabled: *false | _
}

// ---------------------------------------------------------------------------
// #PrinterColumn — ValueObject (mirrors CRD spec.additionalPrinterColumns)
// ---------------------------------------------------------------------------

// #PrinterColumn describes one additional column for the generic CRD list view.
#PrinterColumn: {
	// name is the column header label, e.g. "Replicas".
	name: string & strings.MinRunes(1) & strings.MaxRunes(64)

	// jsonPath is the RFC 6901 / JSONPath expression to extract the value,
	// e.g. ".spec.replicas", ".status.phase".
	jsonPath: string & strings.MinRunes(1)

	// columnType is the Kubernetes printer column type hint.
	// Used to format the extracted value for display.
	columnType: "string" | "integer" | "number" | "boolean" | "date"
	columnType: *"string" | _

	// priority determines column visibility (0 = always visible, >0 = wide mode only).
	priority: int & >=0
	priority: *0 | _
}

// ---------------------------------------------------------------------------
// #ResourceKindCatalog — AggregateRoot
// ---------------------------------------------------------------------------

// #ResourceKindCatalog is the aggregate root for the full resource kind registry.
// Owned by ResourceDescriptorRegistry in resource_browser. The catalog is the
// single source of truth for which kinds are navigable, what sidebar category
// they appear in, and what operations are permitted.
#ResourceKindCatalog: {
	// clusterId identifies which cluster this catalog instance belongs to.
	// The catalog is per-cluster because dynamic CRD kinds differ per cluster.
	clusterId: string & =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// catalogVersion is a monotonically increasing integer incremented on every
	// catalog mutation (CRD added or removed). Emitted in CRDCatalogUpdated events.
	catalogVersion: int & >=1

	// kinds is the full list of registered resource kind descriptors.
	// 51 standard kinds are always present; additional entries are CRD kinds.
	kinds: [...#ResourceKindDescriptor]

	// crdGroups is the ordered list of discovered CRD API group names.
	// Used by the sidebar tree to render the Custom Resources section.
	// Sorted alphabetically. Refreshed on every CRDCatalogUpdated event.
	crdGroups: [...string & strings.MinRunes(1)]
}
