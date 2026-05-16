// Views/Helm/HelmStatusBadge.swift — app_shell bounded context
// DDD role: View — reusable Helm release status pill badge
// ADR ref: ADR-0015 (Helm native phased)

import SwiftUI
import HelmManagement

// MARK: - HelmStatusBadge

/// Pill badge rendering a ``ReleaseStatus`` with colour + icon.
///
/// Mirrors `StatusBadge` from the workloads module but uses Helm-specific
/// status semantics and colours per ADR-0015 §Status mapping.
public struct HelmStatusBadge: View {

    private let status: ReleaseStatus

    public init(status: ReleaseStatus) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .imageScale(.small)
                .foregroundStyle(status.badgeColor)
            Text(status.rawValue)
                .font(.caption.monospacedDigit())
                .foregroundStyle(status.badgeColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(status.badgeColor.opacity(0.12), in: Capsule())
    }
}

// MARK: - ReleaseStatus display extensions

extension ReleaseStatus {

    /// Accent colour for the badge pill.
    public var badgeColor: Color {
        switch self {
        case .deployed:                             return .green
        case .failed:                               return .red
        case .superseded, .uninstalled:             return .secondary
        case .pendingInstall, .pendingUpgrade, .pendingRollback: return .orange
        }
    }

    /// SF Symbol name for the badge icon.
    public var systemImage: String {
        switch self {
        case .deployed:          return "checkmark.circle.fill"
        case .failed:            return "xmark.circle.fill"
        case .superseded:        return "arrow.uturn.backward.circle"
        case .uninstalled:       return "trash.circle"
        case .pendingInstall:    return "clock.fill"
        case .pendingUpgrade:    return "arrow.up.circle"
        case .pendingRollback:   return "arrow.counterclockwise.circle"
        }
    }
}
