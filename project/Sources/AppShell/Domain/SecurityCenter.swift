// Domain/SecurityCenter.swift — app_shell bounded context
// DDD role: Value object — Security Center taxonomy and sub-entry descriptor
// ADR ref: ADR-0068 (Security Center sidebar surface and content)

import Foundation
import SharedKernel

// MARK: - SecurityCenterEntry

/// Enumeration of Security Center sub-entries in fixed ADR-0068 display order.
///
/// Drives sidebar taxonomy in ``SidebarTree/securityCenterChildren`` and
/// the disclosure state persistence key `securityCenterExpanded` in the
/// per-cluster view state (ADR-0025 / ADR-0026).
public enum SecurityCenterEntry: CaseIterable, Sendable, Hashable {
    /// Cluster-level security posture overview (pods as root, PSA labels, network policies, mTLS).
    case overview
    /// Per-image inventory derived from running pod workloads.
    case images
    /// Per-namespace inventory of pod resources breaching security baselines.
    case resources
    /// Per-role RBAC privilege audit sorted by privilege level.
    case roles

    // MARK: Display

    /// Human-readable label for the sub-entry.
    public var title: String {
        switch self {
        case .overview:   return "Overview"
        case .images:     return "Images"
        case .resources:  return "Resources"
        case .roles:      return "Roles"
        }
    }

    /// SF Symbol name for the sub-entry icon.
    public var systemImage: String {
        switch self {
        case .overview:   return "chart.bar.xaxis"
        case .images:     return "photo.stack"
        case .resources:  return "exclamationmark.shield"
        case .roles:      return "person.badge.key"
        }
    }

    /// Maps this entry to the ``SidebarNode`` leaf case.
    public var sidebarNode: SidebarNode {
        switch self {
        case .overview:   return .securityOverviewEntry
        case .images:     return .securityImagesEntry
        case .resources:  return .securityResourcesEntry
        case .roles:      return .securityRolesEntry
        }
    }

    /// Maps this entry to the ``DocumentTab`` kind for the given cluster.
    public func documentTab(clusterId: ClusterId) -> DocumentTab {
        switch self {
        case .overview:   return .securityOverview(clusterId: clusterId)
        case .images:     return .securityImages(clusterId: clusterId)
        case .resources:  return .securityResources(clusterId: clusterId)
        case .roles:      return .securityRoles(clusterId: clusterId)
        }
    }
}

// MARK: - SecurityCenterDisclosureState

/// Per-cluster disclosure state for the Security Center sidebar section.
///
/// Persisted alongside other category disclosure flags per ADR-0025 / ADR-0026.
/// Matches the `securityCenterExpanded` field described in ADR-0068
/// §"Confirmation".
public struct SecurityCenterDisclosureState: Sendable, Codable, Hashable {
    /// Whether the Security Center section is expanded in the sidebar.
    public var isExpanded: Bool

    public init(isExpanded: Bool = true) {
        self.isExpanded = isExpanded
    }

    /// Default expanded state (expanded on first load per ADR-0068).
    public static let `default` = SecurityCenterDisclosureState(isExpanded: true)
}
