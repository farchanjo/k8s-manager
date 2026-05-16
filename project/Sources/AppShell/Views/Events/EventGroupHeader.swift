// Views/Events/EventGroupHeader.swift — app_shell bounded context
// DDD role: View — sticky section header for time-bucketed event groups (Onda 3)

import SwiftUI

// MARK: - EventGroupHeader

/// Sticky timestamp section header for the grouped events scroll view.
///
/// Example headers: "Last 5 minutes", "Last hour", "Older".
/// Shown pinned at the top of each `LazyVStack` section.
@MainActor
public struct EventGroupHeader: View {

    // MARK: Input

    public let groupKey: String
    public let count: Int

    // MARK: Init

    public init(groupKey: String, count: Int) {
        self.groupKey = groupKey
        self.count = count
    }

    // MARK: Body

    public var body: some View {
        HStack(spacing: 6) {
            Text(groupKey)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }
}
