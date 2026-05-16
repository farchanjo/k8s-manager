// Views/Detail/Sections/EventsSection.swift — app_shell bounded context
// DDD role: View — recent events list in the resource detail drawer
// ADR ref: ADR-0021 (detail drawer — Onda 2)

import SwiftUI
import ResourceBrowser

// MARK: - EventsSection

/// Shows the last 5 Kubernetes events related to the selected resource.
///
/// Each row displays: event type chip (Normal/Warning), reason, lastSeen age,
/// and a truncated message preview. Empty state is shown when no events exist.
@MainActor
public struct EventsSection: View {

    public let events: [EventRow]
    /// Called when the user taps "View all events" to open the full timeline tab.
    public let onViewAll: (() -> Void)?

    public init(events: [EventRow], onViewAll: (() -> Void)? = nil) {
        self.events = events
        self.onViewAll = onViewAll
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader
            eventList
        }
    }

    // MARK: Private views

    private var sectionHeader: some View {
        HStack {
            Text("Events (\(events.count))")
                .font(.headline)
            Spacer()
            if let onViewAll {
                Button("View all", action: onViewAll)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var eventList: some View {
        if events.isEmpty {
            Text("No recent events.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(12)
        } else {
            VStack(spacing: 1) {
                ForEach(events) { event in
                    eventRow(event)
                    if event.id != events.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func eventRow(_ event: EventRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            eventTypeChip(event.eventType)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.reason)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(event.lastSeen)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(event.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func eventTypeChip(_ type: EventSummary.EventType) -> some View {
        let isWarning = type == .warning
        let color: Color = isWarning ? .orange : .blue
        return Text(type.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
