// Domain/SidebarTree.swift — app_shell bounded context
// DDD role: ValueObject — sidebar navigation taxonomy
// ADR ref: ADR-0050 (resource navigation taxonomy), ADR-0051 (sidebar tree structure)

import Foundation
import SharedKernel

// MARK: - ResourceKind constants

/// Well-known `ResourceKind` values used by `SidebarNode` to open `DocumentTab`s.
///
/// These are compile-time constants that mirror the standard Kubernetes API groups
/// defined in ADR-0050. Dynamic CRD kinds are handled via `SidebarNode.customResourceKind`.
public extension ResourceKind {
    // Workloads
    static let pods        = ResourceKind(group: "",     version: "v1",    kind: "Pod")
    static let deployments = ResourceKind(group: "apps", version: "v1",    kind: "Deployment")
    static let daemonSets  = ResourceKind(group: "apps", version: "v1",    kind: "DaemonSet")
    static let statefulSets = ResourceKind(group: "apps", version: "v1",   kind: "StatefulSet")
    static let replicaSets  = ResourceKind(group: "apps", version: "v1",   kind: "ReplicaSet")
    static let replicationControllers = ResourceKind(group: "", version: "v1", kind: "ReplicationController")
    static let jobs       = ResourceKind(group: "batch", version: "v1",    kind: "Job")
    static let cronJobs   = ResourceKind(group: "batch", version: "v1",    kind: "CronJob")
    // Config
    static let configMaps = ResourceKind(group: "",     version: "v1",    kind: "ConfigMap")
    static let secrets    = ResourceKind(group: "",     version: "v1",    kind: "Secret")
    static let resourceQuotas = ResourceKind(group: "", version: "v1",    kind: "ResourceQuota")
    static let limitRanges    = ResourceKind(group: "", version: "v1",    kind: "LimitRange")
    static let horizontalPodAutoscalers = ResourceKind(
        group: "autoscaling", version: "v2", kind: "HorizontalPodAutoscaler"
    )
    static let podDisruptionBudgets = ResourceKind(group: "policy",              version: "v1", kind: "PodDisruptionBudget")
    static let priorityClasses      = ResourceKind(group: "scheduling.k8s.io",   version: "v1", kind: "PriorityClass")
    static let runtimeClasses       = ResourceKind(group: "node.k8s.io",         version: "v1", kind: "RuntimeClass")
    static let leases               = ResourceKind(group: "coordination.k8s.io", version: "v1", kind: "Lease")
    static let mutatingWebhookConfigurations = ResourceKind(
        group: "admissionregistration.k8s.io", version: "v1", kind: "MutatingWebhookConfiguration"
    )
    static let validatingWebhookConfigurations = ResourceKind(
        group: "admissionregistration.k8s.io", version: "v1", kind: "ValidatingWebhookConfiguration"
    )
    // Network
    static let services       = ResourceKind(group: "",                  version: "v1", kind: "Service")
    static let endpoints      = ResourceKind(group: "",                  version: "v1", kind: "Endpoints")
    static let endpointSlices = ResourceKind(group: "discovery.k8s.io",  version: "v1", kind: "EndpointSlice")
    static let ingresses      = ResourceKind(group: "networking.k8s.io", version: "v1", kind: "Ingress")
    static let ingressClasses = ResourceKind(group: "networking.k8s.io", version: "v1", kind: "IngressClass")
    static let networkPolicies = ResourceKind(group: "networking.k8s.io", version: "v1", kind: "NetworkPolicy")
    // Storage
    static let persistentVolumeClaims = ResourceKind(group: "",               version: "v1", kind: "PersistentVolumeClaim")
    static let persistentVolumes      = ResourceKind(group: "",               version: "v1", kind: "PersistentVolume")
    static let storageClasses         = ResourceKind(group: "storage.k8s.io", version: "v1", kind: "StorageClass")
    static let volumeSnapshots = ResourceKind(
        group: "snapshot.storage.k8s.io", version: "v1", kind: "VolumeSnapshot"
    )
    static let volumeSnapshotClasses = ResourceKind(
        group: "snapshot.storage.k8s.io", version: "v1", kind: "VolumeSnapshotClass"
    )
    static let csiDrivers = ResourceKind(group: "storage.k8s.io", version: "v1", kind: "CSIDriver")
    // Access Control
    static let serviceAccounts        = ResourceKind(group: "",                               version: "v1", kind: "ServiceAccount")
    static let clusterRoles           = ResourceKind(group: "rbac.authorization.k8s.io",     version: "v1", kind: "ClusterRole")
    static let roles                  = ResourceKind(group: "rbac.authorization.k8s.io",     version: "v1", kind: "Role")
    static let clusterRoleBindings    = ResourceKind(group: "rbac.authorization.k8s.io",     version: "v1", kind: "ClusterRoleBinding")
    static let roleBindings           = ResourceKind(group: "rbac.authorization.k8s.io",     version: "v1", kind: "RoleBinding")
    static let certificateSigningRequests = ResourceKind(group: "certificates.k8s.io",       version: "v1", kind: "CertificateSigningRequest")
    // Cluster meta
    static let namespaceKind          = ResourceKind(group: "", version: "v1", kind: "Namespace")
    static let helmRelease            = ResourceKind(group: "helm.sh", version: "v3", kind: "HelmRelease")
}

// MARK: - SidebarNode

/// Typed node in the Lens-style hierarchical sidebar tree.
///
/// Conforms to `Hashable`, `Sendable`, and `Identifiable` so it can drive
/// SwiftUI `OutlineGroup` and `List(selection:)` bindings directly.
///
/// Group cases (`workloads`, `config`, etc.) expose their children via
/// ``children`` and return `true` from ``isExpandable``.
/// Leaf cases return `nil` from ``children`` so `OutlineGroup` treats them
/// as non-expandable items.
///
/// ADR-0050 — every leaf case maps to one ``DocumentTab`` via
/// ``toDocumentTab(clusterId:)``.
public enum SidebarNode: Hashable, Sendable, Identifiable {

    // MARK: Top-level leaves
    case overview
    case applications
    case nodes

    // MARK: Workloads group + leaves
    case workloads
    case workloadKind(ResourceKind)

    // MARK: Config group + leaves
    case config
    case configKind(ResourceKind)

    // MARK: Network group + leaves
    case network
    case networkKind(ResourceKind)

    // MARK: Storage group + leaves
    case storage
    case storageKind(ResourceKind)

    // MARK: Single-kind top-level entries
    case namespaces
    case events

    // MARK: Helm group + leaves
    case helm
    case helmCharts
    case helmReleases

    // MARK: Access Control group + leaves
    case accessControl
    case rbacKind(ResourceKind)

    // MARK: Custom Resources group (dynamic)
    case customResources
    case customResourceGroup(String)          // e.g. "argoproj.io"
    case customResourceKind(GroupVersionResource)

    // MARK: Security Center group + leaves (ADR-0068)
    case securityCenter
    /// Security Center: cluster-level posture overview.
    case securityOverviewEntry
    /// Security Center: container image inventory.
    case securityImagesEntry
    /// Security Center: pod resource and baseline audit.
    case securityResourcesEntry
    /// Security Center: RBAC role privilege audit.
    case securityRolesEntry

    // MARK: Cluster Operations
    case clusterOperations
    case apiResources
    case applyYAML

    // MARK: - Identifiable

    /// Deterministic stable string id derived from the case and associated values.
    public var id: String {
        switch self {
        case .overview:          return "overview"
        case .applications:      return "applications"
        case .nodes:             return "nodes"
        case .workloads:         return "workloads"
        case .config:            return "config"
        case .network:           return "network"
        case .storage:           return "storage"
        case .namespaces:        return "namespaces"
        case .events:            return "events"
        case .helm:              return "helm"
        case .helmCharts:        return "helm.charts"
        case .helmReleases:      return "helm.releases"
        case .accessControl:     return "access-control"
        case .customResources:   return "custom-resources"
        case .securityCenter:          return "security-center"
        case .securityOverviewEntry:   return "security-center.overview"
        case .securityImagesEntry:     return "security-center.images"
        case .securityResourcesEntry:  return "security-center.resources"
        case .securityRolesEntry:      return "security-center.roles"
        case .clusterOperations:       return "cluster-operations"
        case .apiResources:      return "api-resources"
        case .applyYAML:         return "apply-yaml"
        case .workloadKind(let k):        return "workload.\(k.kind)"
        case .configKind(let k):          return "config.\(k.kind)"
        case .networkKind(let k):         return "network.\(k.kind)"
        case .storageKind(let k):         return "storage.\(k.kind)"
        case .rbacKind(let k):            return "rbac.\(k.kind)"
        case .customResourceGroup(let g): return "crd.group.\(g)"
        case .customResourceKind(let gvr):
            return "crd.\(gvr.group).\(gvr.version).\(gvr.resource)"
        }
    }

    // MARK: - Display

    /// Human-readable label for the sidebar row.
    public var title: String {
        switch self {
        case .overview:          return "Overview"
        case .applications:      return "Applications"
        case .nodes:             return "Nodes"
        case .workloads:         return "Workloads"
        case .config:            return "Config"
        case .network:           return "Network"
        case .storage:           return "Storage"
        case .namespaces:        return "Namespaces"
        case .events:            return "Events"
        case .helm:              return "Helm"
        case .helmCharts:        return "Charts"
        case .helmReleases:      return "Releases"
        case .accessControl:     return "Access Control"
        case .customResources:   return "Custom Resources"
        case .securityCenter:         return "Security Center"
        case .securityOverviewEntry:  return "Overview"
        case .securityImagesEntry:    return "Images"
        case .securityResourcesEntry: return "Resources"
        case .securityRolesEntry:     return "Roles"
        case .clusterOperations:      return "Cluster Operations"
        case .apiResources:      return "API Resources"
        case .applyYAML:         return "Apply YAML"
        case .workloadKind(let k):        return k.kind + "s"
        case .configKind(let k):          return k.kind + "s"
        case .networkKind(let k):         return k.kind + "s"
        case .storageKind(let k):         return k.kind + "s"
        case .rbacKind(let k):            return k.kind + "s"
        case .customResourceGroup(let g): return g
        case .customResourceKind(let gvr): return gvr.resource
        }
    }

    /// SF Symbol name for the sidebar row icon.
    public var systemImage: String {
        switch self {
        case .overview:          return "square.grid.2x2"
        case .applications:      return "app.gift"
        case .nodes:             return "server.rack"
        case .workloads:         return "square.stack.3d.up"
        case .config:            return "wrench.and.screwdriver"
        case .network:           return "network"
        case .storage:           return "internaldrive"
        case .namespaces:        return "folder"
        case .events:            return "calendar.badge.clock"
        case .helm:              return "shippingbox"
        case .helmCharts:        return "doc.richtext"
        case .helmReleases:      return "shippingbox.fill"
        case .accessControl:     return "lock.shield"
        case .customResources:   return "puzzlepiece.extension"
        case .securityCenter:         return "lock.shield.fill"
        case .securityOverviewEntry:  return "chart.bar.xaxis"
        case .securityImagesEntry:    return "photo.stack"
        case .securityResourcesEntry: return "exclamationmark.shield"
        case .securityRolesEntry:     return "person.badge.key"
        case .clusterOperations:      return "gearshape.2"
        case .apiResources:      return "list.bullet.rectangle.portrait"
        case .applyYAML:         return "doc.badge.plus"
        case .workloadKind(let k):        return Self.workloadSymbol(for: k)
        case .configKind(let k):          return Self.configSymbol(for: k)
        case .networkKind(let k):         return Self.networkSymbol(for: k)
        case .storageKind(let k):         return Self.storageSymbol(for: k)
        case .rbacKind(let k):            return Self.rbacSymbol(for: k)
        case .customResourceGroup:        return "puzzlepiece"
        case .customResourceKind:         return "puzzlepiece.fill"
        }
    }

    // MARK: - Children (for OutlineGroup)

    /// Returns the child nodes for expandable group cases, or `nil` for leaf cases.
    ///
    /// `OutlineGroup` uses a non-nil children accessor to determine disclosure.
    /// Returning `nil` (not an empty array) marks a node as a leaf.
    public var children: [SidebarNode]? {
        switch self {
        case .workloads:         return SidebarTree.workloadChildren
        case .config:            return SidebarTree.configChildren
        case .network:           return SidebarTree.networkChildren
        case .storage:           return SidebarTree.storageChildren
        case .helm:              return SidebarTree.helmChildren
        case .accessControl:     return SidebarTree.accessControlChildren
        case .securityCenter:    return SidebarTree.securityCenterChildren
        case .clusterOperations: return SidebarTree.clusterOperationsChildren
        default:                 return nil
        }
    }

    /// `true` when the node has children (i.e. renders a disclosure triangle).
    public var isExpandable: Bool { children != nil }

    // MARK: - Tab mapping

    /// Maps this sidebar node to the `DocumentTab` that should be opened when activated.
    ///
    /// Returns `nil` for pure group headers that have no associated tab (e.g. `.workloads`
    /// when used as an expand-only group without a tab of its own).
    public func toDocumentTab(clusterId: ClusterId) -> DocumentTab? {
        switch self {
        case .overview:                 return .overview(clusterId: clusterId)
        case .applications:             return .applications(clusterId: clusterId)
        case .nodes:                    return .nodes(clusterId: clusterId)
        case .namespaces:               return .namespaces(clusterId: clusterId)
        case .events:                   return .events(clusterId: clusterId, scope: nil)
        case .securityOverviewEntry:    return .securityOverview(clusterId: clusterId)
        case .securityImagesEntry:      return .securityImages(clusterId: clusterId)
        case .securityResourcesEntry:   return .securityResources(clusterId: clusterId)
        case .securityRolesEntry:       return .securityRoles(clusterId: clusterId)
        case .apiResources:             return .apiResources(clusterId: clusterId)
        case .applyYAML:                return .applyYAML(clusterId: clusterId)
        case .helmReleases:             return .resourceList(clusterId: clusterId, kind: .helmRelease, namespace: nil)
        case .workloadKind(let k):
            return .resourceList(clusterId: clusterId, kind: k, namespace: nil)
        case .configKind(let k):
            return .resourceList(clusterId: clusterId, kind: k, namespace: nil)
        case .networkKind(let k):
            return .resourceList(clusterId: clusterId, kind: k, namespace: nil)
        case .storageKind(let k):
            return .resourceList(clusterId: clusterId, kind: k, namespace: nil)
        case .rbacKind(let k):
            return .resourceList(clusterId: clusterId, kind: k, namespace: nil)
        case .customResourceKind(let gvr):
            return .customResource(clusterId: clusterId, gvr: gvr)
        // Group headers and non-tab leaves return nil
        case .workloads, .config, .network, .storage,
             .helm, .helmCharts,
             .accessControl, .customResources,
             .securityCenter,
             .clusterOperations,
             .customResourceGroup:
            return nil
        }
    }

    // MARK: - Private SF Symbol helpers

    private static func workloadSymbol(for kind: ResourceKind) -> String {
        switch kind.kind {
        case "Pod":                   return "cpu"
        case "Deployment":            return "arrow.triangle.2.circlepath"
        case "DaemonSet":             return "square.grid.3x3"
        case "StatefulSet":           return "cylinder.split.1x2"
        case "ReplicaSet":            return "rectangle.split.2x2"
        case "ReplicationController": return "arrow.clockwise"
        case "Job":                   return "checkmark.circle"
        case "CronJob":               return "clock"
        default:                      return "square.stack"
        }
    }

    private static func configSymbol(for kind: ResourceKind) -> String {
        switch kind.kind {
        case "ConfigMap":                     return "doc.text"
        case "Secret":                        return "key.fill"
        case "ResourceQuota":                 return "gauge"
        case "LimitRange":                    return "slider.horizontal.3"
        case "HorizontalPodAutoscaler":       return "arrow.up.arrow.down"
        case "PodDisruptionBudget":           return "shield.lefthalf.filled"
        case "PriorityClass":                 return "list.number"
        case "RuntimeClass":                  return "cpu.fill"
        case "Lease":                         return "timer"
        case "MutatingWebhookConfiguration": return "arrow.triangle.branch"
        case "ValidatingWebhookConfiguration": return "checkmark.shield"
        default:                              return "doc"
        }
    }

    private static func networkSymbol(for kind: ResourceKind) -> String {
        switch kind.kind {
        case "Service":       return "point.3.connected.trianglepath.dotted"
        case "Endpoints":     return "antenna.radiowaves.left.and.right"
        case "EndpointSlice": return "antenna.radiowaves.left.and.right.circle"
        case "Ingress":       return "arrow.right.to.line"
        case "IngressClass":  return "arrow.right.to.line.circle"
        case "NetworkPolicy": return "network.badge.shield.half.filled"
        default:              return "network"
        }
    }

    private static func storageSymbol(for kind: ResourceKind) -> String {
        switch kind.kind {
        case "PersistentVolumeClaim": return "externaldrive.badge.person.crop"
        case "PersistentVolume":      return "externaldrive"
        case "StorageClass":          return "archivebox"
        case "VolumeSnapshot":        return "camera.circle"
        case "VolumeSnapshotClass":   return "camera.circle.fill"
        case "CSIDriver":             return "externaldrive.connected.to.line.below"
        default:                      return "internaldrive"
        }
    }

    private static func rbacSymbol(for kind: ResourceKind) -> String {
        switch kind.kind {
        case "ServiceAccount":              return "person.badge.key"
        case "ClusterRole":                 return "shield.fill"
        case "Role":                        return "shield"
        case "ClusterRoleBinding":          return "person.2.badge.gearshape"
        case "RoleBinding":                 return "person.badge.plus"
        case "CertificateSigningRequest":   return "checkmark.seal"
        default:                            return "lock"
        }
    }
}

// MARK: - SidebarTree

/// Factory for the standard sidebar category list (14 top-level nodes).
///
/// Matches the tree structure defined in ADR-0050 and ADR-0051.
public enum SidebarTree {

    // MARK: - Standard categories (14 top-level nodes)

    /// Returns the 14 top-level sidebar nodes in display order.
    public static func standardCategories() -> [SidebarNode] {
        [
            .overview,
            .applications,
            .nodes,
            .workloads,
            .config,
            .network,
            .storage,
            .namespaces,
            .events,
            .helm,
            .accessControl,
            .customResources,
            .securityCenter,
            .clusterOperations,
        ]
    }

    // MARK: - Children per group

    /// 9 workload child nodes (Overview is implicit at the group level).
    static let workloadChildren: [SidebarNode] = [
        .workloadKind(.pods),
        .workloadKind(.deployments),
        .workloadKind(.daemonSets),
        .workloadKind(.statefulSets),
        .workloadKind(.replicaSets),
        .workloadKind(.replicationControllers),
        .workloadKind(.jobs),
        .workloadKind(.cronJobs),
    ]

    /// Config child nodes per ADR-0050.
    static let configChildren: [SidebarNode] = [
        .configKind(.configMaps),
        .configKind(.secrets),
        .configKind(.resourceQuotas),
        .configKind(.limitRanges),
        .configKind(.horizontalPodAutoscalers),
        .configKind(.podDisruptionBudgets),
        .configKind(.priorityClasses),
        .configKind(.runtimeClasses),
        .configKind(.leases),
        .configKind(.mutatingWebhookConfigurations),
        .configKind(.validatingWebhookConfigurations),
    ]

    /// Network child nodes per ADR-0050.
    static let networkChildren: [SidebarNode] = [
        .networkKind(.services),
        .networkKind(.endpoints),
        .networkKind(.endpointSlices),
        .networkKind(.ingresses),
        .networkKind(.ingressClasses),
        .networkKind(.networkPolicies),
    ]

    /// Storage child nodes per ADR-0050.
    static let storageChildren: [SidebarNode] = [
        .storageKind(.persistentVolumeClaims),
        .storageKind(.persistentVolumes),
        .storageKind(.storageClasses),
        .storageKind(.volumeSnapshots),
        .storageKind(.volumeSnapshotClasses),
        .storageKind(.csiDrivers),
    ]

    /// Helm child nodes.
    static let helmChildren: [SidebarNode] = [
        .helmCharts,
        .helmReleases,
    ]

    /// Access Control child nodes per ADR-0050.
    static let accessControlChildren: [SidebarNode] = [
        .rbacKind(.serviceAccounts),
        .rbacKind(.clusterRoles),
        .rbacKind(.roles),
        .rbacKind(.clusterRoleBindings),
        .rbacKind(.roleBindings),
        .rbacKind(.certificateSigningRequests),
    ]

    /// Security Center child nodes per ADR-0068 §"Sub-entry contracts".
    ///
    /// Fixed order: Overview, Images, Resources, Roles.
    static let securityCenterChildren: [SidebarNode] = [
        .securityOverviewEntry,
        .securityImagesEntry,
        .securityResourcesEntry,
        .securityRolesEntry,
    ]

    /// Cluster Operations child nodes.
    static let clusterOperationsChildren: [SidebarNode] = [
        .apiResources,
        .applyYAML,
    ]
}
