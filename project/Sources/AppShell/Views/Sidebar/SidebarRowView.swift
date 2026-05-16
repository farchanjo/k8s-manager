// Views/Sidebar/SidebarRowView.swift — app_shell bounded context
// DDD role: View
// ADR ref: ADR-0050 (resource navigation taxonomy), ADR-0021 (design system)

import SwiftUI
import SharedKernel

// MARK: - SidebarRowView

/// Single row in the Lens-style hierarchical sidebar tree.
///
/// Renders `(icon, title, count?, disclosure?)` for any `SidebarNode` value.
/// Resource counts (e.g. "Pods (42)") are displayed when a non-nil
/// `count` is provided by the parent via the `SidebarRowView.init`.
///
/// The view deliberately contains no state — all updates flow from
/// `SidebarTreeViewModel` via `SidebarTreeView`.
public struct SidebarRowView: View {

    // MARK: Properties

    let node: SidebarNode
    /// Optional resource count shown in a trailing badge.
    let count: Int?

    // MARK: Init

    public init(node: SidebarNode, count: Int? = nil) {
        self.node = node
        self.count = count
    }

    // MARK: Body

    public var body: some View {
        Label {
            labelText
        } icon: {
            Image(systemName: node.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
        }
        .badge(count.map { Text("\($0)") })
        .accessibilityLabel(node.title)
    }

    // MARK: Private

    @ViewBuilder
    private var labelText: some View {
        if let count {
            HStack(spacing: 4) {
                Text(node.title)
                Text("(\(count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(node.title)
        }
    }
}

// MARK: - ClusterHeaderRow

/// Sticky header row that identifies the active cluster at the top of the sidebar.
///
/// Displays the cluster display-name, a connection indicator dot, and
/// the cluster avatar color derived from `ClusterAvatarColor.deterministic`.
public struct ClusterHeaderRow: View {

    let name: String
    let isConnected: Bool

    public init(name: String, isConnected: Bool) {
        self.name = name
        self.isConnected = isConnected
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .accessibilityLabel(isConnected ? "Connected" : "Disconnected")

            Text(name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(isConnected ? "connected" : "disconnected")")
    }
}
