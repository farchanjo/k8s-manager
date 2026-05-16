// Views/Events/EventsSummaryBar.swift — app_shell bounded context
// DDD role: View — live count strip below the toolbar (Onda 3)

import SwiftUI

// MARK: - EventsSummaryBar

/// Compact status strip showing total, warning, normal counts and last-update age.
///
/// Example: `1,247 events │ 87 warnings │ 1,160 normal │ Last update: 2s ago`
@MainActor
public struct EventsSummaryBar: View {

    // MARK: Input

    public let totalCount: Int
    public let warningCount: Int
    public let normalCount: Int
    public let lastUpdated: Date

    // MARK: Init

    public init(
        totalCount: Int,
        warningCount: Int,
        normalCount: Int,
        lastUpdated: Date
    ) {
        self.totalCount = totalCount
        self.warningCount = warningCount
        self.normalCount = normalCount
        self.lastUpdated = lastUpdated
    }

    // MARK: Body

    public var body: some View {
        HStack(spacing: 0) {
            countChip(label: "events", count: totalCount, color: .primary)
            separator
            countChip(label: "warnings", count: warningCount, color: .orange)
            separator
            countChip(label: "normal", count: normalCount, color: .blue)
            separator
            lastUpdateLabel
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.quinary)
    }

    // MARK: Private helpers

    private func countChip(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(count, format: .number)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private var separator: some View {
        Text("│")
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 8)
    }

    private var lastUpdateLabel: some View {
        Group {
            if lastUpdated == .distantPast {
                Text("No data yet")
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 3) {
                    Text("Last update:")
                        .foregroundStyle(.secondary)
                    Text(lastUpdated, style: .relative)
                        .foregroundStyle(.secondary)
                    Text("ago")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
