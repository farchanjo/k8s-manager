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
public struct StatusBadge: View {

    private let status: WorkloadStatus

    public init(status: WorkloadStatus) {
        self.status = status
    }

    /// Convenience initialiser that parses a raw string.
    ///
    /// - Parameter raw: Kubernetes phase string (e.g. `"Running"`, `"Pending"`).
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

// MARK: - NamespaceFilterPicker

/// Toolbar picker for namespace filtering.
///
/// Bound to an optional `String?`; `nil` means "all namespaces". When the
/// caller supplies a non-empty `namespaces` list (typically loaded from the
/// active cluster), the picker shows every namespace the cluster reports.
/// When the list is empty it falls back to a hard-coded quick-pick set so
/// previews/tests still render.
public struct NamespaceFilterPicker: View {

    @Binding private var selection: String?
    private let namespaces: [String]

    /// Quick-pick namespaces used as a fallback when no dynamic list is supplied.
    private static let quickNamespaces: [String] = [
        "default",
        "kube-system",
        "kube-public",
        "kube-node-lease",
    ]

    public init(selection: Binding<String?>, namespaces: [String] = []) {
        self._selection = selection
        self.namespaces = namespaces
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            Picker("Namespace", selection: $selection) {
                Text("All namespaces").tag(String?.none)
                Divider()
                ForEach(displayNamespaces, id: \.self) { ns in
                    Text(ns).tag(String?.some(ns))
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 160)
        }
    }

    /// Resolves the list shown in the menu, sorted and deduplicated.
    private var displayNamespaces: [String] {
        let raw = namespaces.isEmpty ? Self.quickNamespaces : namespaces
        return Array(Set(raw)).sorted()
    }
}
