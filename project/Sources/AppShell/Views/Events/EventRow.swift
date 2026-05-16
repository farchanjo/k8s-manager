// Views/Events/EventRow.swift — app_shell bounded context
// DDD role: View — single event row in the timeline scroll view (Onda 3)

import SwiftUI
import SharedKernel

// MARK: - EventTimelineRow

/// Per-event row: severity icon, reason chip, object ref, source,
/// timing, count badge, message preview, and context menu.
@MainActor
public struct EventTimelineRow: View {

    // MARK: Input

    public let event: EventEntry
    public let isSelected: Bool
    public let onSelect: (EventEntry) -> Void

    // MARK: State

    @State private var isExpanded = false

    // MARK: Init

    public init(event: EventEntry, isSelected: Bool, onSelect: @escaping (EventEntry) -> Void) {
        self.event = event
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    // MARK: Body

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            severityIcon
            mainContent
            Spacer(minLength: 0)
            trailingMeta
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { onSelect(event) }
        .contextMenu { contextMenuItems }
    }

    // MARK: Sub-views

    private var severityIcon: some View {
        Image(systemName: event.type.systemImage)
            .foregroundStyle(event.type.color)
            .imageScale(.medium)
            .frame(width: 20)
            .padding(.top, 1)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            topLine
            objectLine
            messageLine
        }
    }

    private var topLine: some View {
        HStack(spacing: 6) {
            reasonChip
            Text(event.source)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var objectLine: some View {
        HStack(spacing: 4) {
            Text(event.objectKind)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("/")
                .font(.caption2)
                .foregroundStyle(.quaternary)
            Text(event.objectName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
            if let ns = event.objectNamespace {
                Text("(\(ns))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var messageLine: some View {
        Text(event.message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(isExpanded ? nil : 2)
            .onTapGesture { isExpanded.toggle() }
    }

    private var trailingMeta: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(event.lastSeen)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if event.count > 1 {
                countBadge
            }
        }
        .padding(.top, 1)
    }

    private var countBadge: some View {
        Text("×\(event.count)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var reasonChip: some View {
        Text(event.reason)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(event.type.color.opacity(0.12), in: Capsule())
            .foregroundStyle(event.type.color)
    }

    private var background: some ShapeStyle {
        isSelected
            ? AnyShapeStyle(Color.accentColor.opacity(0.08))
            : AnyShapeStyle(Color.clear)
    }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Copy message") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(event.message, forType: .string)
        }
        Button("Copy as YAML") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(yamlRepresentation, forType: .string)
        }
        Divider()
        Button("Expand message") { isExpanded = true }
        Button("Collapse message") { isExpanded = false }
    }

    private var yamlRepresentation: String {
        """
        apiVersion: v1
        kind: Event
        metadata:
          uid: \(event.id)
          namespace: \(event.objectNamespace ?? "")
        type: \(event.type.rawValue)
        reason: \(event.reason)
        involvedObject:
          kind: \(event.objectKind)
          name: \(event.objectName)
        source:
          component: \(event.source)
        message: "\(event.message)"
        firstTimestamp: \(event.firstSeen)
        lastTimestamp: \(event.lastSeen)
        count: \(event.count)
        """
    }
}
