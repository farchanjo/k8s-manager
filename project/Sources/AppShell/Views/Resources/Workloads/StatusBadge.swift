// Views/Resources/Workloads/StatusBadge.swift — app_shell bounded context
// DDD role: View — reusable status pill badge
// ADR ref: ADR-0050 (Onda 2 resource list views)

import SwiftUI

// MARK: - WorkloadStatus

/// Visual status category shared across workload kinds.
///
/// Maps raw Kubernetes phase/condition strings to a closed display set.
public enum WorkloadStatus: String, Sendable, Hashable {
    case running    = "Running"
    case pending    = "Pending"
    case succeeded  = "Succeeded"
    case failed     = "Failed"
    case unknown    = "Unknown"
    case terminating = "Terminating"
    case healthy    = "Healthy"
    case degraded   = "Degraded"
    case complete   = "Complete"
    case active     = "Active"
    case suspended  = "Suspended"

    /// Accent color per status.
    public var color: Color {
        switch self {
        case .running, .healthy, .succeeded, .complete, .active:
            return .green
        case .pending:
            return .yellow
        case .failed, .degraded:
            return .red
        case .terminating:
            return .orange
        case .unknown, .suspended:
            return .secondary
        }
    }

    /// SF Symbol name per status.
    public var systemImage: String {
        switch self {
        case .running:      return "circle.fill"
        case .pending:      return "clock.fill"
        case .succeeded:    return "checkmark.circle.fill"
        case .complete:     return "checkmark.circle.fill"
        case .failed:       return "xmark.circle.fill"
        case .unknown:      return "questionmark.circle.fill"
        case .terminating:  return "arrow.counterclockwise.circle.fill"
        case .healthy:      return "heart.circle.fill"
        case .degraded:     return "exclamationmark.circle.fill"
        case .active:       return "play.circle.fill"
        case .suspended:    return "pause.circle.fill"
        }
    }

    /// Parses a raw Kubernetes status string to a `WorkloadStatus`.
    ///
    /// - Parameter raw: Case-insensitive phase string from the API server.
    public static func from(raw: String) -> WorkloadStatus {
        switch raw.lowercased() {
        case "running":     return .running
        case "pending":     return .pending
        case "succeeded":   return .succeeded
        case "failed":      return .failed
        case "terminating": return .terminating
        case "complete", "completed": return .complete
        case "active":      return .active
        case "suspended":   return .suspended
        case "healthy":     return .healthy
        case "degraded":    return .degraded
        default:            return .unknown
        }
    }
}

// MARK: - StatusBadge

/// Pill badge rendering a ``WorkloadStatus`` with color + icon.
///
/// - Deprecated: Use ``StatusChip`` with ``StatusChipSemantic`` instead (ADR-0062).
@available(*, deprecated, message: "Use StatusChip + StatusChipSemantic (ADR-0062)", renamed: "StatusChip")
public struct StatusBadge: View {

    private let status: WorkloadStatus

    @available(*, deprecated, message: "Use StatusChip + StatusChipSemantic (ADR-0062)", renamed: "StatusChip.init(variant:label:)")
    public init(status: WorkloadStatus) {
        self.status = status
    }

    /// Convenience initialiser that parses a raw string.
    ///
    /// - Parameter raw: Kubernetes phase string (e.g. `"Running"`, `"Pending"`).
    @available(*, deprecated, message: "Use StatusChip + StatusChipSemantic (ADR-0062)", renamed: "StatusChip.init(variant:label:)")
    public init(raw: String) {
        self.status = WorkloadStatus.from(raw: raw)
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .imageScale(.small)
                .foregroundStyle(status.color)
            Text(status.rawValue)
                .font(.caption.monospacedDigit())
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.12), in: Capsule())
    }
}

