// Views/Chrome/NotificationsPopover.swift — app_shell bounded context
// DDD role: Leaf view — notifications history popover
// ADR ref: ADR-0051 (top-right chrome), ADR-0032 (toast notification system)

import SwiftUI

// MARK: - NotificationsPopover

/// Popover anchored to `NotificationsButton` showing the last 50 notification entries.
///
/// Marks all entries as read on appear. Supports inline "Clear" action via the view model.
@MainActor
public struct NotificationsPopover: View {

    let viewModel: TopRightChromeViewModel

    public init(viewModel: TopRightChromeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 340, height: 400)
        .onAppear { viewModel.markAllRead() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Notifications")
                .font(.headline)
            Spacer()
            Button("Clear") { viewModel.clearAll() }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .disabled(viewModel.notifications.isEmpty)
                .accessibilityLabel("Clear all notifications")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if viewModel.notifications.isEmpty {
            emptyState
        } else {
            notificationList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No notifications")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notificationList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.notifications) { entry in
                    NotificationRow(entry: entry)
                    Divider().padding(.leading, 36)
                }
            }
        }
    }
}

// MARK: - NotificationRow

/// Single row in `NotificationsPopover`.
@MainActor
private struct NotificationRow: View {

    let entry: NotificationEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            unreadIndicator
            severityIcon
            details
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(entry.isRead ? Color.clear : Color.accentColor.opacity(0.04))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Private

    private var unreadIndicator: some View {
        Circle()
            .fill(entry.isRead ? Color.clear : Color.accentColor)
            .frame(width: 6, height: 6)
            .padding(.top, 5)
    }

    private var severityIcon: some View {
        Image(systemName: entry.severity.systemImage)
            .font(.system(size: 14))
            .foregroundStyle(entry.severity.color)
            .frame(width: 16)
            .padding(.top, 1)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer()
                Text(relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let subtitle = entry.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var relativeTime: String {
        guard let date = ISO8601DateFormatter().date(from: entry.timestampRFC3339) else {
            return ""
        }
        let elapsed = Date.now.timeIntervalSince(date)
        switch elapsed {
        case ..<60:       return "just now"
        case ..<3_600:    return "\(Int(elapsed / 60)) min ago"
        case ..<86_400:   return "\(Int(elapsed / 3_600)) hr ago"
        default:          return "\(Int(elapsed / 86_400)) d ago"
        }
    }

    private var accessibilityText: String {
        var parts = [entry.severity.rawValue, entry.title]
        if let subtitle = entry.subtitle { parts.append(subtitle) }
        parts.append(relativeTime)
        return parts.joined(separator: ". ")
    }
}
