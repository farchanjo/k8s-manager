// Views/Editor/DryRunPreviewPanel.swift — app_shell bounded context
// DDD role: View — dry-run managed-fields diff + warnings + conflict list (Onda 3)
// ADR ref: ADR-0030 (diff preview pane), ADR-0012 (field ownership conflicts)

import SwiftUI
import ResourceBrowser

// MARK: - DryRunPreviewPanel

/// Right-side panel showing the result of a server-side dry-run PATCH.
///
/// Displays:
/// - Managed-fields diff (additions in green, removals in red, unchanged collapsed).
/// - API-server Warning header strings.
/// - SSA field-ownership conflicts with force-ownership toggle.
public struct DryRunPreviewPanel: View {

    let result: DryRunResult
    @State private var showUnchanged: Bool = false

    public init(result: DryRunResult) {
        self.result = result
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    diffSection
                    if !result.warnings.isEmpty { warningsSection }
                    if !result.conflicts.isEmpty { conflictsSection }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Private sections

    private var panelHeader: some View {
        HStack {
            Label("Dry-Run Preview", systemImage: "doc.badge.clock")
                .font(.subheadline.bold())
            Spacer()
            Toggle("Show unchanged", isOn: $showUnchanged)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var diffSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionTitle("Managed Fields Diff")
            ForEach(visibleLines) { line in
                diffLineView(line)
            }
            if hiddenUnchangedCount > 0 && !showUnchanged {
                Text("… \(hiddenUnchangedCount) unchanged lines hidden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("API Server Warnings")
            ForEach(result.warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var conflictsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Field Ownership Conflicts")
            ForEach(result.conflicts, id: \.fieldPath) { conflict in
                conflictRow(conflict)
            }
        }
    }

    private func conflictRow(_ conflict: FieldConflict) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(conflict.fieldPath)
                .font(.caption.monospaced())
                .foregroundStyle(.red)
            Text("Owned by: \(conflict.currentManager)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func diffLineView(_ line: DiffLine) -> some View {
        HStack(spacing: 4) {
            Text(linePrefix(for: line.kind))
                .font(.caption.monospaced())
                .foregroundStyle(lineColor(for: line.kind))
                .frame(width: 12, alignment: .leading)
                .accessibilityHidden(true)
            Text(line.text)
                .font(.caption.monospaced())
                .foregroundStyle(lineColor(for: line.kind))
        }
        .padding(.vertical, 1)
        .background(lineBackground(for: line.kind))
        .accessibilityLabel(accessibilityLabel(for: line))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    // MARK: Helpers

    private var visibleLines: [DiffLine] {
        showUnchanged ? result.diffLines : result.diffLines.filter { $0.kind != .unchanged }
    }

    private var hiddenUnchangedCount: Int {
        result.diffLines.filter { $0.kind == .unchanged }.count
    }

    private func linePrefix(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "-"
        case .unchanged: return " "
        }
    }

    private func lineColor(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .unchanged: return .primary
        }
    }

    private func lineBackground(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return Color.green.opacity(0.08)
        case .removed: return Color.red.opacity(0.08)
        case .unchanged: return .clear
        }
    }

    private func accessibilityLabel(for line: DiffLine) -> String {
        switch line.kind {
        case .added: return "added: \(line.text)"
        case .removed: return "removed: \(line.text)"
        case .unchanged: return line.text
        }
    }
}
