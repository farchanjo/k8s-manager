// Domain/ResourceDescriptor.swift — resource_browser bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/resource_browser/schemas/resource_descriptor.cue
// ADR refs: ADR-0013 (kind catalogue), ADR-0012 (mutation guard)

import Foundation

// MARK: - GroupVersionKind

/// Encodes the three-part Kubernetes type identity (GVK).
///
/// The `group` field is empty for core/v1 kinds (e.g., Pod, Service).
/// Mirrors `#GroupVersionKind` from `resource_descriptor.cue`.
public struct GroupVersionKind: Hashable, Sendable, Codable {
    /// API group (e.g. `"apps"`, `"batch"`, `"networking.k8s.io"`).
    /// Empty string for the core group (`v1`).
    public let group: String

    /// API version string (e.g. `"v1"`, `"v1beta1"`).
    public let version: String

    /// PascalCase Kubernetes kind name (e.g. `"Pod"`, `"Deployment"`).
    public let kind: String

    public init(group: String, version: String, kind: String) {
        self.group = group
        self.version = version
        self.kind = kind
    }

    /// Convenience for core/v1 kinds where the group is empty.
    public static func core(_ kind: String) -> GroupVersionKind {
        GroupVersionKind(group: "", version: "v1", kind: kind)
    }
}

// MARK: - SupportedVerb

/// Closed set of Kubernetes API verbs the resource_browser context may issue.
///
/// Mirrors `#SupportedVerb` from `resource_descriptor.cue`.
public enum SupportedVerb: String, Hashable, Sendable, Codable, CaseIterable {
    /// Fetch a single resource manifest.
    case get
    /// Fetch all instances of a kind.
    case list
    /// Open a long-lived watch stream.
    case watch
    /// Create a new instance from a submitted manifest.
    case create
    /// Replace the full manifest of an existing instance.
    case update
    /// Apply a partial update (SSA is the default strategy; ADR-0012).
    case patch
    /// Delete a single instance. Requires double-confirm per ADR-0012.
    case delete
}

// MARK: - SupportedSubresource

/// Closed set of Kubernetes subresources the resource_browser context may access.
///
/// Mirrors `#SupportedSubresource` from `resource_descriptor.cue`.
public enum SupportedSubresource: String, Hashable, Sendable, Codable, CaseIterable {
    /// Read or update the `.status` sub-object.
    case status
    /// Read or update the `/scale` subresource (replica count).
    case scale
    /// Stream container logs via the `/log` subresource (Pod only).
    case logs
    /// Open an interactive shell via `/exec`. Reserved for a future release.
    case exec
    /// Open a port-forward tunnel via `/portforward`. Reserved for future release.
    case portforward
}

// MARK: - ResourceDescriptor

/// Immutable description of a Kubernetes resource kind.
///
/// Constructed at startup from the static catalogue defined in ADR-0013 and
/// extended at runtime by discovered CRD entries. Carries no instance-level
/// data — it describes the kind itself.
///
/// Mirrors `#ResourceDescriptor` from `resource_descriptor.cue`.
public struct ResourceDescriptor: Hashable, Sendable, Codable {
    /// Uniquely identifies the Kubernetes API type.
    public let gvk: GroupVersionKind

    /// Lowercase plural name used in API paths (e.g. `"pods"`, `"deployments"`).
    public let plural: String

    /// `true` when instances of this kind are scoped to a Kubernetes namespace.
    public let namespaced: Bool

    /// Closed set of API verbs the resource_browser context may issue.
    public let supportedVerbs: [SupportedVerb]

    /// Subresources the resource_browser context may access for this kind.
    public let supportedSubresources: [SupportedSubresource]

    /// Kubernetes API category labels (e.g. `["all"]`, `["workloads"]`).
    public let categories: [String]

    public init(
        gvk: GroupVersionKind,
        plural: String,
        namespaced: Bool,
        supportedVerbs: [SupportedVerb],
        supportedSubresources: [SupportedSubresource] = [],
        categories: [String] = []
    ) {
        self.gvk = gvk
        self.plural = plural
        self.namespaced = namespaced
        self.supportedVerbs = supportedVerbs
        self.supportedSubresources = supportedSubresources
        self.categories = categories
    }
}

// MARK: - KindCatalogue

/// In-memory registry of `ResourceDescriptor` values.
///
/// Static entries are loaded at application start from the list defined in
/// ADR-0013. Dynamic CRD entries are merged at runtime.
public struct KindCatalogue: Sendable {
    private var entries: [GroupVersionKind: ResourceDescriptor]

    /// Initialises the catalogue with the ADR-0013 static entries.
    public init(entries: [ResourceDescriptor] = KindCatalogue.staticEntries) {
        self.entries = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.gvk, $0) }
        )
    }

    /// Returns the descriptor for a GVK, or `nil` if not registered.
    public func descriptor(for gvk: GroupVersionKind) -> ResourceDescriptor? {
        entries[gvk]
    }

    /// All registered descriptors in stable (alphabetical kind name) order.
    public var all: [ResourceDescriptor] {
        entries.values.sorted { $0.gvk.kind < $1.gvk.kind }
    }

    /// Registers (or replaces) a descriptor. Used for CRD dynamic discovery.
    public mutating func register(_ descriptor: ResourceDescriptor) {
        entries[descriptor.gvk] = descriptor
    }

    /// Removes a previously registered descriptor. Used when a CRD is deleted.
    public mutating func remove(gvk: GroupVersionKind) {
        entries.removeValue(forKey: gvk)
    }

    // MARK: ADR-0013 static catalogue

    /// The closed-set catalogue of well-known kinds as specified in ADR-0013.
    public static let staticEntries: [ResourceDescriptor] = [
        // core/v1
        ResourceDescriptor(
            gvk: .core("Pod"),
            plural: "pods",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.logs, .status],
            categories: ["all", "workloads"]
        ),
        ResourceDescriptor(
            gvk: .core("Service"),
            plural: "services",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.status],
            categories: ["all"]
        ),
        ResourceDescriptor(
            gvk: .core("ConfigMap"),
            plural: "configmaps",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete]
        ),
        ResourceDescriptor(
            gvk: .core("Secret"),
            plural: "secrets",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete]
        ),
        ResourceDescriptor(
            gvk: .core("Endpoints"),
            plural: "endpoints",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch]
        ),
        ResourceDescriptor(
            gvk: .core("PersistentVolumeClaim"),
            plural: "persistentvolumeclaims",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.status]
        ),
        ResourceDescriptor(
            gvk: .core("PersistentVolume"),
            plural: "persistentvolumes",
            namespaced: false,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.status]
        ),
        ResourceDescriptor(
            gvk: .core("Namespace"),
            plural: "namespaces",
            namespaced: false,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.status]
        ),
        ResourceDescriptor(
            gvk: .core("ServiceAccount"),
            plural: "serviceaccounts",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete]
        ),
        // apps/v1
        ResourceDescriptor(
            gvk: GroupVersionKind(group: "apps", version: "v1", kind: "Deployment"),
            plural: "deployments",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.scale, .status],
            categories: ["all", "workloads"]
        ),
        ResourceDescriptor(
            gvk: GroupVersionKind(group: "apps", version: "v1", kind: "DaemonSet"),
            plural: "daemonsets",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.status],
            categories: ["all", "workloads"]
        ),
        ResourceDescriptor(
            gvk: GroupVersionKind(group: "apps", version: "v1", kind: "StatefulSet"),
            plural: "statefulsets",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.scale, .status],
            categories: ["all", "workloads"]
        ),
        ResourceDescriptor(
            gvk: GroupVersionKind(group: "apps", version: "v1", kind: "ReplicaSet"),
            plural: "replicasets",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.scale, .status],
            categories: ["all", "workloads"]
        ),
        // batch/v1
        ResourceDescriptor(
            gvk: GroupVersionKind(group: "batch", version: "v1", kind: "Job"),
            plural: "jobs",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.status]
        ),
        ResourceDescriptor(
            gvk: GroupVersionKind(group: "batch", version: "v1", kind: "CronJob"),
            plural: "cronjobs",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.status]
        ),
        // networking.k8s.io/v1
        ResourceDescriptor(
            gvk: GroupVersionKind(group: "networking.k8s.io", version: "v1", kind: "Ingress"),
            plural: "ingresses",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.status]
        ),
        ResourceDescriptor(
            gvk: GroupVersionKind(group: "networking.k8s.io", version: "v1", kind: "NetworkPolicy"),
            plural: "networkpolicies",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete]
        ),
        // storage.k8s.io/v1
        ResourceDescriptor(
            gvk: GroupVersionKind(group: "storage.k8s.io", version: "v1", kind: "StorageClass"),
            plural: "storageclasses",
            namespaced: false,
            supportedVerbs: [.list, .get, .watch, .patch, .delete]
        ),
        // rbac.authorization.k8s.io/v1
        ResourceDescriptor(
            gvk: GroupVersionKind(group: "rbac.authorization.k8s.io", version: "v1", kind: "Role"),
            plural: "roles",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete]
        ),
        ResourceDescriptor(
            gvk: GroupVersionKind(group: "rbac.authorization.k8s.io", version: "v1", kind: "RoleBinding"),
            plural: "rolebindings",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch, .patch, .delete]
        ),
        ResourceDescriptor(
            gvk: GroupVersionKind(group: "rbac.authorization.k8s.io", version: "v1", kind: "ClusterRole"),
            plural: "clusterroles",
            namespaced: false,
            supportedVerbs: [.list, .get, .watch, .patch, .delete]
        ),
        ResourceDescriptor(
            gvk: GroupVersionKind(
                group: "rbac.authorization.k8s.io",
                version: "v1",
                kind: "ClusterRoleBinding"
            ),
            plural: "clusterrolebindings",
            namespaced: false,
            supportedVerbs: [.list, .get, .watch, .patch, .delete]
        ),
        // apiextensions.k8s.io/v1
        ResourceDescriptor(
            gvk: GroupVersionKind(
                group: "apiextensions.k8s.io",
                version: "v1",
                kind: "CustomResourceDefinition"
            ),
            plural: "customresourcedefinitions",
            namespaced: false,
            supportedVerbs: [.list, .get, .watch, .patch, .delete],
            supportedSubresources: [.status]
        ),
    ]
}
