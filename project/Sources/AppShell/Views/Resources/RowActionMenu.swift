// Views/Resources/RowActionMenu.swift — app_shell bounded context
// DDD role: View + ValueObject — uniform per-row action menu
// ADR ref: ADR-0061 (row action menu uniform shape)

import SwiftUI

// MARK: - KindFamily

/// Resource kind family grouping per ADR-0050 and ADR-0061.
public enum KindFamily: Sendable, Hashable {
    case workloads
    case config
    case network
    case storage
    case accessControl
    case cluster
    case customResources
}

// MARK: - ResourceKindDescriptor (action layer)

/// Describes a resource kind for action-menu purposes.
///
/// Drives which family-specific items are appended to the base action set.
public struct RowActionContext: Sendable, Hashable {
    /// Kubernetes kind string (e.g. `"Deployment"`, `"Pod"`).
    public let kind: String
    /// Resource name for display and action payload.
    public let name: String
    /// Namespace; `nil` for cluster-scoped resources.
    public let namespace: String?
    /// Kind family determining which extension items are shown.
    public let family: KindFamily
    /// Whether the operator holds RBAC delete permission.
    public let canDelete: Bool
    /// Whether the operator holds RBAC create/update permission (for Edit YAML).
    public let canMutate: Bool

    public init(
        kind: String,
        name: String,
        namespace: String? = nil,
        family: KindFamily,
        canDelete: Bool = true,
        canMutate: Bool = true
    ) {
        self.kind = kind
        self.name = name
        self.namespace = namespace
        self.family = family
        self.canDelete = canDelete
        self.canMutate = canMutate
    }
}

// MARK: - RowAction

/// Value object representing a single menu action per ADR-0061.
public struct RowAction: Sendable, Identifiable, Hashable {
    /// Stable identifier used for equality and testing.
    public let id: String
    /// Human-readable label shown in the menu.
    public let label: String
    /// Keyboard accelerator letter shown next to the item.
    public let acceleratorKey: String
    /// True when the action modifies cluster state.
    public let isMutating: Bool
    /// True when the action requires a two-step confirmation per ADR-0012.
    public let requiresDoubleConfirm: Bool

    public init(
        id: String,
        label: String,
        acceleratorKey: String,
        isMutating: Bool,
        requiresDoubleConfirm: Bool = false
    ) {
        self.id = id
        self.label = label
        self.acceleratorKey = acceleratorKey
        self.isMutating = isMutating
        self.requiresDoubleConfirm = requiresDoubleConfirm
    }
}

// MARK: - RowAction constants

public extension RowAction {
    /// Edit YAML — dispatches `#ApplyYAML`; single-confirm with diff preview.
    static let editYAML = RowAction(
        id: "edit-yaml", label: "Edit YAML",
        acceleratorKey: "e", isMutating: true
    )
    /// View Events — read-only navigation.
    static let viewEvents = RowAction(
        id: "view-events", label: "View Events",
        acceleratorKey: "v", isMutating: false
    )
    /// Copy Resource Link — read-only clipboard write.
    static let copyResourceLink = RowAction(
        id: "copy-resource-link", label: "Copy Resource Link",
        acceleratorKey: "c", isMutating: false
    )
    /// Save YAML — read-only export per ADR-0060.
    static let saveYAML = RowAction(
        id: "save-yaml", label: "Save YAML",
        acceleratorKey: "y", isMutating: false
    )
    /// Delete — double-confirm required per ADR-0012.
    static let delete = RowAction(
        id: "delete", label: "Delete\u{2026}",
        acceleratorKey: "x", isMutating: true, requiresDoubleConfirm: true
    )
    /// Scale — Workloads family (Deployment, StatefulSet, ReplicaSet).
    static let scale = RowAction(
        id: "scale", label: "Scale\u{2026}",
        acceleratorKey: "s", isMutating: true
    )
    /// Rollout Restart — Workloads family (Deployment, StatefulSet, DaemonSet).
    static let rolloutRestart = RowAction(
        id: "rollout-restart", label: "Rollout Restart",
        acceleratorKey: "r", isMutating: true
    )
    /// View Logs — Pod only.
    static let viewLogs = RowAction(
        id: "view-logs", label: "View Logs",
        acceleratorKey: "l", isMutating: false
    )
    /// Open Terminal — Pod only.
    static let openTerminal = RowAction(
        id: "open-terminal", label: "Open Terminal",
        acceleratorKey: "t", isMutating: false
    )
    /// Port Forward — Service (Network family) and Pod (Workloads family).
    static let portForward = RowAction(
        id: "port-forward", label: "Port Forward",
        acceleratorKey: "f", isMutating: false
    )
    /// View Subjects — RoleBinding and ClusterRoleBinding only.
    static let viewSubjects = RowAction(
        id: "view-subjects", label: "View Subjects",
        acceleratorKey: "u", isMutating: false
    )
    /// Reveal Data — Secret only (not a standard ADR-0061 action but preserved).
    static let revealData = RowAction(
        id: "reveal-data", label: "Reveal Data",
        acceleratorKey: "d", isMutating: false
    )
}

// MARK: - RowActionMenuBuilder

/// Value type that constructs the canonical action list for a given resource context.
///
/// Implements the per-family canonical menu shape from ADR-0061. The base set
/// (Edit YAML, View Events, Copy Resource Link, Save YAML, Delete) is identical
/// across all families. Family-specific items are appended after the base set.
/// Items that do not apply to the specific kind are **omitted** (not disabled).
public struct RowActionMenuBuilder: Sendable {

    // MARK: Base set (all families)

    private static let baseActions: [RowAction] = [
        .editYAML,
        .viewEvents,
        .copyResourceLink,
        .saveYAML,
        .delete,
    ]

    // MARK: Public API

    /// Builds the ordered canonical action list for the given context.
    ///
    /// - Parameter context: Kind, namespace, family, and RBAC permissions.
    /// - Returns: Ordered array of `RowAction` values appropriate for the kind.
    public static func actions(for context: RowActionContext) -> [RowAction] {
        var result = baseActions
        appendFamilyActions(for: context, into: &result)
        return result
    }

    // MARK: Private

    private static func appendFamilyActions(
        for context: RowActionContext,
        into result: inout [RowAction]
    ) {
        switch context.family {
        case .workloads:
            appendWorkloadActions(kind: context.kind, into: &result)
        case .network:
            appendNetworkActions(kind: context.kind, into: &result)
        case .accessControl:
            appendAccessControlActions(kind: context.kind, into: &result)
        case .config:
            appendConfigActions(kind: context.kind, into: &result)
        case .storage, .cluster, .customResources:
            break
        }
    }

    private static func appendWorkloadActions(kind: String, into result: inout [RowAction]) {
        let scalableKinds: Set<String> = ["Deployment", "StatefulSet", "ReplicaSet"]
        let restartableKinds: Set<String> = ["Deployment", "StatefulSet", "DaemonSet"]

        if scalableKinds.contains(kind) { result.append(.scale) }
        if restartableKinds.contains(kind) { result.append(.rolloutRestart) }
        if kind == "Pod" {
            result.append(.viewLogs)
            result.append(.openTerminal)
            result.append(.portForward)
        }
    }

    private static func appendNetworkActions(kind: String, into result: inout [RowAction]) {
        if kind == "Service" { result.append(.portForward) }
    }

    private static func appendAccessControlActions(kind: String, into result: inout [RowAction]) {
        let bindingKinds: Set<String> = ["RoleBinding", "ClusterRoleBinding"]
        if bindingKinds.contains(kind) { result.append(.viewSubjects) }
    }

    private static func appendConfigActions(kind: String, into result: inout [RowAction]) {
        if kind == "Secret" { result.append(.revealData) }
    }
}

// MARK: - RowActionMenu (SwiftUI)

/// Reusable three-dot menu button with the canonical ADR-0061 action set.
///
/// Callers supply a `RowActionContext` and an `onAction` closure. The menu
/// builds its items via `RowActionMenuBuilder` and calls `onAction` for every
/// item the operator selects.
public struct RowActionMenu: View {

    private let context: RowActionContext
    private let onAction: (RowAction) -> Void

    /// Creates a row action menu.
    ///
    /// - Parameters:
    ///   - context: Kind, namespace, family, and RBAC permissions for the row.
    ///   - onAction: Called with the selected `RowAction` when the operator picks an item.
    public init(context: RowActionContext, onAction: @escaping (RowAction) -> Void) {
        self.context = context
        self.onAction = onAction
    }

    public var body: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24, height: 24)
        .accessibilityLabel("Actions for \(context.name)")
        .accessibilityHint("Opens the resource action menu")
    }

    // MARK: Private

    @ViewBuilder
    private var menuItems: some View {
        let actions = RowActionMenuBuilder.actions(for: context)
        ForEach(actions) { action in
            if action.id == "delete" {
                Divider()
                Button(role: .destructive) {
                    onAction(action)
                } label: {
                    Label(action.label, systemImage: "trash")
                }
            } else {
                Button {
                    onAction(action)
                } label: {
                    Text(action.label)
                }
            }
        }
    }
}
