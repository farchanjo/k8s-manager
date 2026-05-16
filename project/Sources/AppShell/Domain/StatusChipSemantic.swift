// Domain/StatusChipSemantic.swift — app_shell bounded context
// DDD role: ValueObject
// ADR ref: ADR-0062 (status chips and node conditions)

import Foundation

// MARK: - StatusChipVariant

/// Semantic severity variant for a status chip.
///
/// Each variant maps to a design-token foreground colour and an SF Symbol icon
/// as specified in ADR-0062 §StatusChip SwiftUI view contract.
public enum StatusChipVariant: String, Sendable, Hashable, CaseIterable {
    /// Healthy, ready, or fully available. Token: `statusHealthy`.
    case success
    /// Degraded, pending, or under pressure. Token: `statusWarning`.
    case warning
    /// Failed, unavailable, or critical condition. Token: `statusError`.
    case error
    /// Informational, non-alarm state. Token: `accentBrand`.
    case info
    /// Terminal, inactive, or unknown state. Token: `statusUnknown`.
    case neutral

    /// SF Symbol icon name for this variant.
    ///
    /// Icons are chosen so that state is distinguishable by shape alone,
    /// satisfying WCAG 1.4.1 (colour not the sole differentiator).
    public var systemImage: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .neutral: return "circle.fill"
        }
    }

    /// Severity rank used when selecting the worst chip for list-row compaction.
    ///
    /// Higher value = higher severity. Order: `error(4) > warning(3) > success(2) > info(1) > neutral(0)`.
    public var severityRank: Int {
        switch self {
        case .error:   return 4
        case .warning: return 3
        case .success: return 2
        case .info:    return 1
        case .neutral: return 0
        }
    }
}

// MARK: - NodeConditionStatus

/// Raw Kubernetes condition `status` field values.
public enum NodeConditionStatus: String, Sendable {
    case `true`    = "True"
    case `false`   = "False"
    case unknown   = "Unknown"

    /// Parses the raw API string; defaults to `.unknown` on unrecognised values.
    public static func from(raw: String) -> NodeConditionStatus {
        NodeConditionStatus(rawValue: raw) ?? .unknown
    }
}

// MARK: - NodeConditionChip

/// Resolved chip parameters for a single Kubernetes node condition.
public struct NodeConditionChip: Sendable, Hashable {
    /// Chip severity variant.
    public let variant: StatusChipVariant
    /// Localised chip label (e.g., `"Ready"`, `"MemoryPressure"`).
    public let label: String
    /// Raw condition message from the API, surfaced as a hover tooltip.
    public let tooltip: String?

    public init(variant: StatusChipVariant, label: String, tooltip: String? = nil) {
        self.variant = variant
        self.label = label
        self.tooltip = tooltip
    }
}

// MARK: - StatusChipSemantic

/// Pure mapping functions from Kubernetes API values to `StatusChipVariant`.
///
/// This type carries no state and imports no infrastructure. It is the sole
/// source of truth for the semantic rules defined in ADR-0062.
public enum StatusChipSemantic {

    // MARK: Node conditions

    /// Maps a Kubernetes `Ready` condition to a chip.
    ///
    /// - Parameters:
    ///   - status: The `status` field value (`"True"`, `"False"`, `"Unknown"`).
    ///   - message: Optional `message` field from the condition, used as tooltip.
    public static func readyChip(status: String, message: String? = nil) -> NodeConditionChip {
        switch NodeConditionStatus.from(raw: status) {
        case .true:    return .init(variant: .success, label: "Ready",    tooltip: message)
        case .false:   return .init(variant: .error,   label: "NotReady", tooltip: message)
        case .unknown: return .init(variant: .warning, label: "Unknown",  tooltip: message)
        }
    }

    /// Maps a pressure-type condition (`MemoryPressure`, `DiskPressure`, `PIDPressure`) to an
    /// optional chip. Returns `nil` when the condition is healthy (`status == "False"`).
    ///
    /// - Parameters:
    ///   - type: Condition type string as returned by the API (e.g., `"MemoryPressure"`).
    ///   - status: The `status` field value.
    ///   - message: Optional `message` field used as tooltip.
    public static func pressureChip(
        type: String,
        status: String,
        message: String? = nil
    ) -> NodeConditionChip? {
        switch NodeConditionStatus.from(raw: status) {
        case .true:    return .init(variant: .error,   label: type, tooltip: message)
        case .false:   return nil
        case .unknown: return .init(variant: .warning, label: type, tooltip: message)
        }
    }

    /// Maps a `NetworkUnavailable` condition to an optional chip.
    /// Returns `nil` when the condition is healthy (`status == "False"`).
    ///
    /// - Parameters:
    ///   - status: The `status` field value.
    ///   - message: Optional `message` field used as tooltip.
    public static func networkUnavailableChip(
        status: String,
        message: String? = nil
    ) -> NodeConditionChip? {
        switch NodeConditionStatus.from(raw: status) {
        case .true:    return .init(variant: .error,   label: "NetworkUnavailable", tooltip: message)
        case .false:   return nil
        case .unknown: return .init(variant: .warning, label: "NetworkUnavailable", tooltip: message)
        }
    }

    /// Returns a `SchedulingDisabled` chip when the node carries the unschedulable taint.
    ///
    /// - Parameter isUnschedulable: `true` when `node.spec.unschedulable == true` or the
    ///   `node.kubernetes.io/unschedulable` taint is present.
    public static func schedulingDisabledChip(
        isUnschedulable: Bool
    ) -> NodeConditionChip? {
        guard isUnschedulable else { return nil }
        return .init(variant: .warning, label: "SchedulingDisabled")
    }

    // MARK: Pod phase

    /// Maps a Kubernetes pod phase string to a chip variant and label.
    ///
    /// `CrashLoopBackOff` waiting reason overrides the phase chip regardless of phase value.
    ///
    /// - Parameters:
    ///   - phase: `pod.status.phase` string (e.g., `"Running"`, `"Pending"`).
    ///   - allContainersReady: `true` when every container in the pod has `ready == true`.
    ///   - hasCrashLoopBackOff: `true` when any container's `state.waiting.reason` is
    ///     `"CrashLoopBackOff"`.
    ///   - message: Optional `pod.status.message` or container waiting message for tooltip.
    public static func podPhaseChip(
        phase: String,
        allContainersReady: Bool = true,
        hasCrashLoopBackOff: Bool = false,
        message: String? = nil
    ) -> NodeConditionChip {
        if hasCrashLoopBackOff {
            return .init(variant: .error, label: "CrashLoopBackOff", tooltip: message)
        }
        switch phase.lowercased() {
        case "running" where allContainersReady:
            return .init(variant: .success, label: "Running",   tooltip: message)
        case "running":
            return .init(variant: .warning, label: "Degraded",  tooltip: message)
        case "pending":
            return .init(variant: .warning, label: "Pending",   tooltip: message)
        case "failed":
            return .init(variant: .error,   label: "Failed",    tooltip: message)
        case "succeeded":
            return .init(variant: .neutral, label: "Succeeded", tooltip: message)
        default:
            return .init(variant: .warning, label: "Unknown",   tooltip: message)
        }
    }

    // MARK: Worst-chip compaction

    /// Selects the single highest-severity chip from a collection for list-row compaction.
    ///
    /// When the input is empty, returns `nil`. The severity order is
    /// `error > warning > success > info > neutral` per ADR-0062.
    ///
    /// - Parameter chips: Non-empty collection of resolved chips.
    public static func worstChip(from chips: [NodeConditionChip]) -> NodeConditionChip? {
        chips.max { $0.variant.severityRank < $1.variant.severityRank }
    }
}
