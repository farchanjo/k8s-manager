// Domain/DocumentTab.swift — app_shell bounded context
// DDD role: Value object — open tab descriptor
// ADR ref: ADR-0050 (resource navigation taxonomy + tab system)

import Foundation
import SharedKernel

// MARK: - ResourceKind

/// Kubernetes group-version-kind tuple identifying a resource type.
///
/// Mirrors the `apiVersion`/`kind` pair from the Kubernetes API machinery.
/// An empty `group` string represents the core API group (`v1`).
public struct ResourceKind: Hashable, Sendable, Codable {
    /// API group (e.g. `"apps"`, `"batch"`) or `""` for the core group.
    public let group: String
    /// API version (e.g. `"v1"`, `"v1beta1"`).
    public let version: String
    /// Kind name (e.g. `"Pod"`, `"Deployment"`).
    public let kind: String

    public init(group: String, version: String, kind: String) {
        self.group = group
        self.version = version
        self.kind = kind
    }

    /// Computed `apiVersion` string as used in Kubernetes manifests.
    public var apiVersion: String {
        group.isEmpty ? version : "\(group)/\(version)"
    }
}

// MARK: - GroupVersionResource
// Defined in `SharedKernel` (SharedIds.swift) so both `AppShell` and
// `ResourceBrowser` resolve it without a circular module dependency.

// MARK: - ResourceRef

/// Lightweight reference to a specific Kubernetes resource instance.
///
/// Used in tab types that target a single resource (detail view, YAML editor,
/// logs, exec) to carry enough coordinates for the API call without importing
/// a full domain entity.
public struct ResourceRef: Hashable, Sendable, Codable {
    /// Kind descriptor for the referenced resource.
    public let kind: ResourceKind
    /// Namespace, or `nil` for cluster-scoped resources.
    public let namespace: String?
    /// Resource name.
    public let name: String

    public init(kind: ResourceKind, namespace: String?, name: String) {
        self.kind = kind
        self.namespace = namespace
        self.name = name
    }
}

/// Unambiguous alias for `ResourceRef` when both AppShell and ResourceBrowser
/// are imported in the same file. Tests may use `EditorResourceRef` to refer
/// to the AppShell domain model without hitting the module-name shadow.
public typealias EditorResourceRef = ResourceRef

// MARK: - EventScope

/// Scope filter applied to the events tab.
public enum EventScope: Hashable, Sendable, Codable {
    /// All events across the entire cluster.
    case clusterWide
    /// Events scoped to a single namespace.
    case namespace(String)
    /// Events produced by or about a specific resource.
    case resource(ResourceRef)
}

// MARK: - DocumentTab

/// Enumeration of every tab kind that can appear in the tab bar.
///
/// Each case carries the minimum set of associated values required to render
/// the view and to derive a stable, deterministic `TabId`. Two tabs with
/// identical associated values (i.e. the same `id`) represent the same logical
/// document and `OpenTabsActor.openTab(_:)` focuses rather than duplicates.
///
/// ADR-0050 defines the full taxonomy. Keep case names aligned with the
/// `#TabKind` discriminant defined in `document_tab.cue`.
public enum DocumentTab: Sendable, Identifiable, Hashable {

    // MARK: Cases

    /// Persistent workspace-scoped Welcome tab (ADR-0054).
    ///
    /// Single-instance per workspace, always pinned, never closeable. Renders
    /// the cluster-acquisition launch pad with five canonical start actions
    /// and the Useful Guides section.
    case welcome

    /// Cluster-level overview dashboard.
    case overview(clusterId: ClusterId)

    /// Application workloads panel.
    case applications(clusterId: ClusterId)

    /// Node list and node detail.
    case nodes(clusterId: ClusterId)

    /// Generic resource list for any GVK, optionally scoped to a namespace.
    case resourceList(clusterId: ClusterId, kind: ResourceKind, namespace: String?)

    /// Read-only detail view for a specific resource instance.
    case resourceDetail(clusterId: ClusterId, ref: ResourceRef)

    /// YAML editor with in-flight draft text.
    case yamlEditor(clusterId: ClusterId, ref: ResourceRef, draft: String)

    /// Pod log streaming tab.
    case logs(clusterId: ClusterId, podRef: ResourceRef, container: String?, follow: Bool)

    /// Interactive exec-into-container tab.
    case exec(clusterId: ClusterId, podRef: ResourceRef, container: String?)

    /// Node-level debug shell tab (ephemeral debug Pod via `kubectl debug node`).
    case nodeDebug(clusterId: ClusterId, nodeRef: ResourceRef)

    /// Kubernetes events tab, optionally scoped.
    case events(clusterId: ClusterId, scope: EventScope?)

    /// Helm release detail tab.
    case helmRelease(clusterId: ClusterId, releaseName: String, namespace: String)

    /// Namespace list tab.
    case namespaces(clusterId: ClusterId)

    /// Port-forward session tab identified by a stable UUID.
    case portForward(clusterId: ClusterId, forwardId: UUID)

    /// Custom resource instance list/detail via GVR.
    case customResource(clusterId: ClusterId, gvr: GroupVersionResource)

    /// RBAC / PSA security overview for a cluster.
    case securityOverview(clusterId: ClusterId)

    /// Security Center — container image inventory (ADR-0068).
    case securityImages(clusterId: ClusterId)

    /// Security Center — pod resource and baseline audit (ADR-0068).
    case securityResources(clusterId: ClusterId)

    /// Security Center — RBAC role privilege audit (ADR-0068).
    case securityRoles(clusterId: ClusterId)

    /// API resource discovery browser.
    case apiResources(clusterId: ClusterId)

    /// YAML / JSON apply tool (kubectl apply -f - equivalent).
    case applyYAML(clusterId: ClusterId)

    /// Cluster diagnostics bundle collection.
    case diagnostics(clusterId: ClusterId)

    // MARK: Identifiable

    /// Deterministic `TabId` derived from associated values.
    ///
    /// The identity intentionally excludes mutable "editor state" fields such as
    /// `draft` in `.yamlEditor` and `follow` in `.logs` so that toggling follow
    /// does not open a second tab; only structurally distinct navigation targets
    /// produce distinct ids.
    public var id: TabId {
        TabId(raw: stableKey)
    }

    // MARK: ClusterId extraction

    /// The cluster this tab belongs to, or `nil` for workspace-scoped tabs.
    ///
    /// Workspace-scoped tabs (currently only `.welcome`) carry no cluster
    /// association — they exist at the application workspace level.
    public var clusterId: ClusterId? {
        switch self {
        case .welcome:
            return nil
        case .overview(let c),
             .applications(let c),
             .nodes(let c),
             .namespaces(let c),
             .securityOverview(let c),
             .securityImages(let c),
             .securityResources(let c),
             .securityRoles(let c),
             .apiResources(let c),
             .applyYAML(let c),
             .diagnostics(let c):
            return c
        case .resourceList(let c, _, _):    return c
        case .resourceDetail(let c, _):     return c
        case .yamlEditor(let c, _, _):      return c
        case .logs(let c, _, _, _):         return c
        case .exec(let c, _, _):            return c
        case .nodeDebug(let c, _):          return c
        case .events(let c, _):             return c
        case .helmRelease(let c, _, _):     return c
        case .portForward(let c, _):        return c
        case .customResource(let c, _):     return c
        }
    }

    // MARK: Workspace scope + closeability

    /// Whether this tab is workspace-scoped rather than cluster-scoped.
    ///
    /// Workspace-scoped tabs persist independently of any cluster and are not
    /// torn down when clusters disconnect.
    public var isWorkspaceScoped: Bool {
        switch self {
        case .welcome:  return true
        default:        return false
        }
    }

    /// Whether the tab bar should render a close affordance for this tab.
    ///
    /// `.welcome` is permanently exempt from the close button per ADR-0054.
    /// All other tabs are closeable. Used by `TabBarView` to conditionally
    /// render the close button and exclude the tab from "close other / close
    /// to right" sweeps.
    public var isCloseable: Bool {
        switch self {
        case .welcome:  return false
        default:        return true
        }
    }

    // MARK: Display

    /// Human-readable tab label shown in the tab chip.
    public var title: String {
        switch self {
        case .welcome:                              return "Welcome"
        case .overview:                             return "Overview"
        case .applications:                         return "Applications"
        case .nodes:                                return "Nodes"
        case .namespaces:                           return "Namespaces"
        case .securityOverview:                     return "Security Overview"
        case .securityImages:                       return "Security: Images"
        case .securityResources:                    return "Security: Resources"
        case .securityRoles:                        return "Security: Roles"
        case .apiResources:                         return "API Resources"
        case .applyYAML:                            return "Apply YAML"
        case .diagnostics:                          return "Diagnostics"
        case .resourceList(_, let kind, let ns):
            return ns.map { "\(kind.kind) (\($0))" } ?? kind.kind
        case .resourceDetail(_, let ref):           return ref.name
        case .yamlEditor(_, let ref, _):            return "Edit \(ref.name)"
        case .logs(_, let pod, let container, _):
            return container.map { "\(pod.name): \($0)" } ?? "\(pod.name) logs"
        case .exec(_, let pod, let container):
            return container.map { "\(pod.name): \($0)" } ?? "exec: \(pod.name)"
        case .nodeDebug(_, let node):
            return "debug: \(node.name)"
        case .events(_, let scope):
            guard let scope else { return "Events" }
            switch scope {
            case .clusterWide:          return "Events"
            case .namespace(let ns):    return "Events (\(ns))"
            case .resource(let ref):    return "Events: \(ref.name)"
            }
        case .helmRelease(_, let name, _):          return name
        case .portForward(_, let id):               return "Forward \(id.uuidString.prefix(8))"
        case .customResource(_, let gvr):           return gvr.resource
        }
    }

    /// SF Symbol name used for the tab chip icon.
    public var systemImage: String {
        switch self {
        case .welcome:          return "hand.wave"
        case .overview:         return "square.grid.2x2"
        case .applications:     return "app.gift"
        case .nodes:            return "server.rack"
        case .resourceList:     return "list.bullet"
        case .resourceDetail:   return "doc.text"
        case .yamlEditor:       return "pencil.and.outline"
        case .logs:             return "text.alignleft"
        case .exec:             return "terminal"
        case .nodeDebug:        return "server.rack"
        case .events:           return "calendar.badge.clock"
        case .helmRelease:      return "shippingbox"
        case .namespaces:       return "folder"
        case .portForward:      return "arrow.left.arrow.right"
        case .customResource:   return "puzzlepiece.extension"
        case .securityOverview:   return "lock.shield"
        case .securityImages:     return "photo.stack"
        case .securityResources:  return "exclamationmark.shield"
        case .securityRoles:      return "person.badge.key"
        case .apiResources:     return "network"
        case .applyYAML:        return "doc.badge.plus"
        case .diagnostics:      return "stethoscope"
        }
    }

    // MARK: Private helpers

    /// Stable string used as the basis for `TabId`.
    ///
    /// Excludes mutable-only fields (`draft`, `follow`) so toggling them
    /// does not open duplicate tabs.
    private var stableKey: String {
        // Workspace-scoped tabs have no cluster — return a fixed identity.
        if case .welcome = self { return "welcome" }
        let c = clusterId?.rawValue ?? "workspace"
        switch self {
        case .welcome:              return "welcome"
        case .overview:             return "overview:\(c)"
        case .applications:         return "applications:\(c)"
        case .nodes:                return "nodes:\(c)"
        case .namespaces:           return "namespaces:\(c)"
        case .securityOverview:     return "security.overview:\(c)"
        case .securityImages:       return "security.images:\(c)"
        case .securityResources:    return "security.resources:\(c)"
        case .securityRoles:        return "security.roles:\(c)"
        case .apiResources:         return "apiresources:\(c)"
        case .applyYAML:            return "applyyaml:\(c)"
        case .diagnostics:          return "diagnostics:\(c)"
        case .resourceList(_, let kind, let ns):
            let nsKey = ns ?? "*"
            return "resourcelist:\(c):\(kind.apiVersion):\(kind.kind):\(nsKey)"
        case .resourceDetail(_, let ref):
            return "resourcedetail:\(c):\(refKey(ref))"
        case .yamlEditor(_, let ref, _):
            return "yamleditor:\(c):\(refKey(ref))"
        case .logs(_, let pod, let container, _):
            return "logs:\(c):\(refKey(pod)):\(container ?? "*")"
        case .exec(_, let pod, let container):
            return "exec:\(c):\(refKey(pod)):\(container ?? "*")"
        case .nodeDebug(_, let node):
            return "nodedebug:\(c):\(refKey(node))"
        case .events(_, let scope):
            return "events:\(c):\(scopeKey(scope))"
        case .helmRelease(_, let name, let ns):
            return "helm:\(c):\(ns):\(name)"
        case .portForward(_, let id):
            return "portforward:\(c):\(id.uuidString)"
        case .customResource(_, let gvr):
            return "customresource:\(c):\(gvr.group):\(gvr.version):\(gvr.resource)"
        }
    }

    private func refKey(_ ref: ResourceRef) -> String {
        "\(ref.kind.apiVersion):\(ref.kind.kind):\(ref.namespace ?? "*"):\(ref.name)"
    }

    private func scopeKey(_ scope: EventScope?) -> String {
        guard let scope else { return "clusterwide" }
        switch scope {
        case .clusterWide:          return "clusterwide"
        case .namespace(let ns):    return "ns:\(ns)"
        case .resource(let ref):    return "ref:\(refKey(ref))"
        }
    }
}

// MARK: - DocumentTab + Codable

/// `DocumentTab` Codable conformance using a tagged-union encoding.
///
/// Stored in `open-tabs.json` for state restoration (ADR-0050 § persistence).
/// The `yamlEditor` `draft` field is persisted so unsaved edits survive relaunches.
extension DocumentTab: Codable {

    private enum CodingKeys: String, CodingKey {
        case type
        case clusterId
        case kind
        case namespace
        case ref
        case nodeRef
        case draft
        case container
        case follow
        case scope
        case releaseName
        case forwardId
        case gvr
    }

    private enum TypeTag: String, Codable {
        case welcome
        case overview, applications, nodes, resourceList, resourceDetail
        case yamlEditor, logs, exec, nodeDebug, events, helmRelease, namespaces
        case portForward, customResource
        case securityOverview, securityImages, securityResources, securityRoles
        case apiResources, applyYAML, diagnostics
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(TypeTag.self, forKey: .type)
        // Welcome tabs are workspace-scoped — no clusterId is encoded.
        if tag == .welcome {
            self = .welcome
            return
        }
        let cid = try c.decode(ClusterId.self, forKey: .clusterId)
        switch tag {
        case .welcome:
            // Unreachable: handled by early return above.
            self = .welcome
        case .overview:          self = .overview(clusterId: cid)
        case .applications:      self = .applications(clusterId: cid)
        case .nodes:             self = .nodes(clusterId: cid)
        case .namespaces:        self = .namespaces(clusterId: cid)
        case .securityOverview:  self = .securityOverview(clusterId: cid)
        case .securityImages:    self = .securityImages(clusterId: cid)
        case .securityResources: self = .securityResources(clusterId: cid)
        case .securityRoles:     self = .securityRoles(clusterId: cid)
        case .apiResources:      self = .apiResources(clusterId: cid)
        case .applyYAML:         self = .applyYAML(clusterId: cid)
        case .diagnostics:       self = .diagnostics(clusterId: cid)
        case .resourceList:
            let kind = try c.decode(ResourceKind.self, forKey: .kind)
            let ns = try c.decodeIfPresent(String.self, forKey: .namespace)
            self = .resourceList(clusterId: cid, kind: kind, namespace: ns)
        case .resourceDetail:
            let ref = try c.decode(ResourceRef.self, forKey: .ref)
            self = .resourceDetail(clusterId: cid, ref: ref)
        case .yamlEditor:
            let ref = try c.decode(ResourceRef.self, forKey: .ref)
            let draft = try c.decode(String.self, forKey: .draft)
            self = .yamlEditor(clusterId: cid, ref: ref, draft: draft)
        case .logs:
            let ref = try c.decode(ResourceRef.self, forKey: .ref)
            let container = try c.decodeIfPresent(String.self, forKey: .container)
            let follow = try c.decode(Bool.self, forKey: .follow)
            self = .logs(clusterId: cid, podRef: ref, container: container, follow: follow)
        case .exec:
            let ref = try c.decode(ResourceRef.self, forKey: .ref)
            let container = try c.decodeIfPresent(String.self, forKey: .container)
            self = .exec(clusterId: cid, podRef: ref, container: container)
        case .nodeDebug:
            let nref = try c.decode(ResourceRef.self, forKey: .nodeRef)
            self = .nodeDebug(clusterId: cid, nodeRef: nref)
        case .events:
            let scope = try c.decodeIfPresent(EventScope.self, forKey: .scope)
            self = .events(clusterId: cid, scope: scope)
        case .helmRelease:
            let name = try c.decode(String.self, forKey: .releaseName)
            let ns = try c.decode(String.self, forKey: .namespace)
            self = .helmRelease(clusterId: cid, releaseName: name, namespace: ns)
        case .portForward:
            let fid = try c.decode(UUID.self, forKey: .forwardId)
            self = .portForward(clusterId: cid, forwardId: fid)
        case .customResource:
            let gvr = try c.decode(GroupVersionResource.self, forKey: .gvr)
            self = .customResource(clusterId: cid, gvr: gvr)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Workspace-scoped tabs (welcome) have no clusterId — encode only the tag.
        if case .welcome = self {
            try c.encode(TypeTag.welcome, forKey: .type)
            return
        }
        try c.encodeIfPresent(clusterId, forKey: .clusterId)
        switch self {
        case .welcome:
            // Unreachable: handled by early return above.
            try c.encode(TypeTag.welcome, forKey: .type)
        case .overview:
            try c.encode(TypeTag.overview, forKey: .type)
        case .applications:
            try c.encode(TypeTag.applications, forKey: .type)
        case .nodes:
            try c.encode(TypeTag.nodes, forKey: .type)
        case .namespaces:
            try c.encode(TypeTag.namespaces, forKey: .type)
        case .securityOverview:
            try c.encode(TypeTag.securityOverview, forKey: .type)
        case .securityImages:
            try c.encode(TypeTag.securityImages, forKey: .type)
        case .securityResources:
            try c.encode(TypeTag.securityResources, forKey: .type)
        case .securityRoles:
            try c.encode(TypeTag.securityRoles, forKey: .type)
        case .apiResources:
            try c.encode(TypeTag.apiResources, forKey: .type)
        case .applyYAML:
            try c.encode(TypeTag.applyYAML, forKey: .type)
        case .diagnostics:
            try c.encode(TypeTag.diagnostics, forKey: .type)
        case .resourceList(_, let kind, let ns):
            try c.encode(TypeTag.resourceList, forKey: .type)
            try c.encode(kind, forKey: .kind)
            try c.encodeIfPresent(ns, forKey: .namespace)
        case .resourceDetail(_, let ref):
            try c.encode(TypeTag.resourceDetail, forKey: .type)
            try c.encode(ref, forKey: .ref)
        case .yamlEditor(_, let ref, let draft):
            try c.encode(TypeTag.yamlEditor, forKey: .type)
            try c.encode(ref, forKey: .ref)
            try c.encode(draft, forKey: .draft)
        case .logs(_, let pod, let container, let follow):
            try c.encode(TypeTag.logs, forKey: .type)
            try c.encode(pod, forKey: .ref)
            try c.encodeIfPresent(container, forKey: .container)
            try c.encode(follow, forKey: .follow)
        case .exec(_, let pod, let container):
            try c.encode(TypeTag.exec, forKey: .type)
            try c.encode(pod, forKey: .ref)
            try c.encodeIfPresent(container, forKey: .container)
        case .nodeDebug(_, let nref):
            try c.encode(TypeTag.nodeDebug, forKey: .type)
            try c.encode(nref, forKey: .nodeRef)
        case .events(_, let scope):
            try c.encode(TypeTag.events, forKey: .type)
            try c.encodeIfPresent(scope, forKey: .scope)
        case .helmRelease(_, let name, let ns):
            try c.encode(TypeTag.helmRelease, forKey: .type)
            try c.encode(name, forKey: .releaseName)
            try c.encode(ns, forKey: .namespace)
        case .portForward(_, let fid):
            try c.encode(TypeTag.portForward, forKey: .type)
            try c.encode(fid, forKey: .forwardId)
        case .customResource(_, let gvr):
            try c.encode(TypeTag.customResource, forKey: .type)
            try c.encode(gvr, forKey: .gvr)
        }
    }
}

// MARK: - DocumentTab + portForward list sentinel

extension DocumentTab {
    /// A well-known UUID used as `forwardId` to indicate a port-forward list tab
    /// (no specific session targeted).
    ///
    /// Convention: `portForward(clusterId:, forwardId: DocumentTab.portForwardListSentinel)`
    /// renders `PortForwardListView`; any other UUID renders `PortForwardDetailView`.
    public static let portForwardListSentinel: UUID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    )!
}

// MARK: - DocumentTab + watchTarget

extension DocumentTab {

    /// The `ResourceKind` that should be watched when this tab is opened.
    ///
    /// Returns `nil` for tab kinds that do not own a watch stream (overview,
    /// yamlEditor, exec, portForward, terminalSession, etc.). Per ADR-0050
    /// only `resourceList`, `resourceDetail`, `applications`, `nodes`,
    /// `namespaces`, and `customResource` tabs require a watch.
    public var watchTarget: ResourceKind? {
        switch self {
        case .resourceList(_, let kind, _):
            return kind
        case .resourceDetail(_, let ref):
            return ref.kind
        case .applications:
            return ResourceKind(group: "apps", version: "v1", kind: "Deployment")
        case .nodes:
            return ResourceKind(group: "", version: "v1", kind: "Node")
        case .namespaces:
            return ResourceKind(group: "", version: "v1", kind: "Namespace")
        case .customResource(_, let gvr):
            return ResourceKind(group: gvr.group, version: gvr.version, kind: gvr.resource)
        default:
            return nil
        }
    }
}
