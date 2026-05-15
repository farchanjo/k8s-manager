// DDD role: ValueObject
package app_shell

// #IconCatalog is the canonical registry of all symbol references used
// in K8sManager. It is the single source of truth for symbol names,
// rendering modes, symbol variants, accessibility labels, and animation
// hints. No SwiftUI view may reference a symbol name that is not declared
// here. Enforced at CI time via the IconView wrapper and a CUE lint rule.
//
// ADR-0028 — SF Symbols and native iconography.
#IconCatalog: {
	// version is incremented on every breaking schema change
	// (field removal, type change). Additive field additions with
	// defaults are non-breaking and do not increment version.
	version: int | *1

	// entries is the ordered list of icon descriptors. Ordering is
	// non-semantic; it is maintained for human readability only.
	entries: [...#IconEntry]
}

// #IconEntry describes one iconographic element in the catalog.
// Every entry must have a unique id slug, a symbol name, and a
// non-empty accessibility label. Entries with isCustomSymbol true
// must use a symbolName prefixed with "k8s.".
#IconEntry: {
	// id is a kebab-case slug used as the stable identifier for
	// this entry in Swift source (mapped to an enum case by the
	// code generator). Format: ^[a-z][a-z0-9-]+$.
	id: string

	// symbolName is the SF Symbols 6 stock name (passed to
	// Image(systemName:)) or the custom .symbolset name (passed to
	// Image(symbolName:)) when isCustomSymbol is true.
	// Custom symbol names must match ^k8s\..
	symbolName: string

	// renderingMode controls how SwiftUI applies color to the
	// symbol layers. The SwiftUI modifier is
	// .symbolRenderingMode(.<renderingMode>).
	renderingMode: "monochrome" | "hierarchical" | "palette" | "multicolor" | *"hierarchical"

	// variant selects the symbol variant applied via .symbolVariant(.<variant>).
	// "default" means no variant modifier is applied.
	variant: "default" | "fill" | "circle" | "square" | "slash" | *"default"

	// accessibilityLabel is the VoiceOver announcement string declared
	// via .accessibilityLabel(). Must be non-empty. Uses natural
	// language (e.g., "Kind: Pod", "Status: Healthy"). Must not be
	// a raw symbol name string.
	accessibilityLabel: string

	// semantic classifies the icon's role in the information architecture.
	semantic: "kind" | "status" | "action" | "navigation" | "brand"

	// isCustomSymbol is true for symbols authored as custom .symbolset
	// assets embedded in Assets.xcassets. These are referenced via
	// Image(symbolName:) rather than Image(systemName:).
	isCustomSymbol: bool | *false

	// macOS14FallbackName is the stock SF Symbols name to use on
	// macOS 14 when the primary symbolName requires macOS 15+.
	// Omit if the primary symbol is available on macOS 14+.
	macOS14FallbackName?: string
}

// #SymbolRenderHint attaches color and animation metadata to an
// #IconEntry for a specific rendering context (e.g., status badge
// in the ApiServerHealth widget). It is not part of the catalog
// directly; it is composed by the IconView wrapper at render time.
#SymbolRenderHint: {
	// tints is an ordered list of color token references used as
	// palette layers. Index 0 = primary layer; index 1 = secondary
	// layer; index 2 = tertiary layer. Referenced tokens must exist
	// in #ColorTokens (design_tokens.cue).
	tints: [...#ColorTokenRef]

	// animation selects the symbolEffect applied to this rendering
	// context. "none" means no effect modifier is applied.
	animation: "none" | "pulse" | "bounce" | "variableColor" | *"none"
}

// #ColorTokenRef is a string reference to a named field in #ColorTokens.
// The CUE validator checks that the referenced name exists in the
// design_tokens.cue schema at lint time.
#ColorTokenRef: string

// --- Catalog instance ---
// The _catalog constant enumerates all current entries. This value
// is exported by the ColorTokenPlugin build plugin alongside the
// generated ColorTokens.swift extension.
_catalog: #IconCatalog & {
	version: 1
	entries: [
		// ── Navigation ──────────────────────────────────────────────────
		{
			id:                 "nav-cluster"
			symbolName:         "rectangle.3.group"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Navigation: Cluster"
			semantic:           "navigation"
			isCustomSymbol:     false
		},
		{
			id:                 "nav-namespace"
			symbolName:         "folder"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Navigation: Namespace"
			semantic:           "navigation"
			isCustomSymbol:     false
		},
		{
			id:                 "nav-assistant"
			symbolName:         "bubble.left.and.bubble.right"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Navigation: AI Assistant"
			semantic:           "navigation"
			isCustomSymbol:     false
		},
		{
			id:                 "nav-metrics"
			symbolName:         "chart.line.uptrend.xyaxis"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Navigation: Metrics"
			semantic:           "navigation"
			isCustomSymbol:     false
		},
		{
			id:                 "nav-settings"
			symbolName:         "gearshape"
			renderingMode:      "monochrome"
			variant:            "default"
			accessibilityLabel: "Navigation: Settings"
			semantic:           "navigation"
			isCustomSymbol:     false
		},

		// ── Resource kinds ───────────────────────────────────────────────
		{
			id:                 "kind-pod"
			symbolName:         "k8s.pod"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: Pod"
			semantic:           "kind"
			isCustomSymbol:     true
		},
		{
			id:                 "kind-deployment"
			symbolName:         "k8s.deployment"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: Deployment"
			semantic:           "kind"
			isCustomSymbol:     true
		},
		{
			id:                 "kind-statefulset"
			symbolName:         "k8s.statefulset"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: StatefulSet"
			semantic:           "kind"
			isCustomSymbol:     true
		},
		{
			id:                 "kind-daemonset"
			symbolName:         "k8s.daemonset"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: DaemonSet"
			semantic:           "kind"
			isCustomSymbol:     true
		},
		{
			id:                 "kind-replicaset"
			symbolName:         "square.3.layers.3d"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: ReplicaSet"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-job"
			symbolName:         "clock"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: Job"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-cronjob"
			symbolName:         "clock.arrow.circlepath"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: CronJob"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-service"
			symbolName:         "antenna.radiowaves.left.and.right"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: Service"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-ingress"
			symbolName:         "arrow.left.and.right.righttriangle.left.righttriangle.right"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: Ingress"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-configmap"
			symbolName:         "doc.text"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: ConfigMap"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-secret"
			symbolName:         "lock.doc"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: Secret"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-pvc"
			symbolName:         "externaldrive"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: PersistentVolumeClaim"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-pv"
			symbolName:         "externaldrive.connected.to.line.below"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: PersistentVolume"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-storageclass"
			symbolName:         "externaldrive.badge.checkmark"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: StorageClass"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-networkpolicy"
			symbolName:         "shield"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: NetworkPolicy"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-role"
			symbolName:         "person.badge.key"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: Role"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-clusterrole"
			symbolName:         "person.badge.key"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: ClusterRole"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-rolebinding"
			symbolName:         "person.2.badge.key"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: RoleBinding"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-clusterrolebinding"
			symbolName:         "person.2.badge.key"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: ClusterRoleBinding"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-serviceaccount"
			symbolName:         "person.crop.circle.badge.checkmark"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: ServiceAccount"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-crd"
			symbolName:         "rectangle.dashed"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: CustomResourceDefinition"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-node"
			symbolName:         "server.rack"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: Node"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-helm-release"
			symbolName:         "shippingbox"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: Helm Release"
			semantic:           "kind"
			isCustomSymbol:     false
		},
		{
			id:                 "kind-endpoint"
			symbolName:         "point.3.connected.trianglepath.dotted"
			renderingMode:      "hierarchical"
			variant:            "default"
			accessibilityLabel: "Kind: Endpoints"
			semantic:           "kind"
			isCustomSymbol:     false
		},

		// ── Actions ──────────────────────────────────────────────────────
		{
			id:                 "action-event"
			symbolName:         "exclamationmark.bubble"
			renderingMode:      "monochrome"
			variant:            "default"
			accessibilityLabel: "Action: View Events"
			semantic:           "action"
			isCustomSymbol:     false
		},
		{
			id:                 "action-log"
			symbolName:         "doc.text.magnifyingglass"
			renderingMode:      "monochrome"
			variant:            "default"
			accessibilityLabel: "Action: View Logs"
			semantic:           "action"
			isCustomSymbol:     false
		},
		{
			id:                 "action-terminal"
			symbolName:         "terminal"
			renderingMode:      "monochrome"
			variant:            "default"
			accessibilityLabel: "Action: Open Terminal"
			semantic:           "action"
			isCustomSymbol:     false
		},
		{
			id:                 "action-port-forward"
			symbolName:         "arrow.up.arrow.down.circle"
			renderingMode:      "monochrome"
			variant:            "default"
			accessibilityLabel: "Action: Port Forward"
			semantic:           "action"
			isCustomSymbol:     false
		},

		// ── Status badges ────────────────────────────────────────────────
		{
			id:                 "status-healthy"
			symbolName:         "checkmark.circle.fill"
			renderingMode:      "palette"
			variant:            "fill"
			accessibilityLabel: "Status: Healthy"
			semantic:           "status"
			isCustomSymbol:     false
		},
		{
			id:                 "status-warning"
			symbolName:         "exclamationmark.triangle.fill"
			renderingMode:      "palette"
			variant:            "fill"
			accessibilityLabel: "Status: Warning"
			semantic:           "status"
			isCustomSymbol:     false
		},
		{
			id:                 "status-error"
			symbolName:         "xmark.octagon.fill"
			renderingMode:      "palette"
			variant:            "fill"
			accessibilityLabel: "Status: Error"
			semantic:           "status"
			isCustomSymbol:     false
		},
		{
			id:                 "status-pending"
			symbolName:         "clock.fill"
			renderingMode:      "palette"
			variant:            "fill"
			accessibilityLabel: "Status: Pending"
			semantic:           "status"
			isCustomSymbol:     false
		},
		{
			id:                 "status-unknown"
			symbolName:         "questionmark.circle"
			renderingMode:      "palette"
			variant:            "default"
			accessibilityLabel: "Status: Unknown"
			semantic:           "status"
			isCustomSymbol:     false
		},

		// ── Brand ────────────────────────────────────────────────────────
		{
			id:                 "brand-app-icon"
			symbolName:         "k8s.helm.wheel"
			renderingMode:      "palette"
			variant:            "default"
			accessibilityLabel: "K8sManager"
			semantic:           "brand"
			isCustomSymbol:     true
		},
	]
}
