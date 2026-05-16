// Views/Logs/LogLineView.swift — app_shell bounded context
// DDD role: View — per-line row in the log stream
// ADR ref: Onda 3

import SwiftUI
import ResourceBrowser
import SharedKernel

// MARK: - LogSeverity + Color

extension LogSeverity {
    /// Display color used by `LogLineView` for severity tinting.
    var color: Color {
        switch self {
        case .error:   return .red
        case .warning: return .orange
        case .info:    return .green
        case .debug:   return .blue
        case .trace:   return .secondary
        }
    }
}

// MARK: - LogLineView

/// Renders a single `LogLine` in the log scroll view.
///
/// Shows: optional timestamp (gray), container badge when multiple containers
/// are visible, and the line content coloured by severity.
/// Highlights search matches with a yellow background.
public struct LogLineView: View {

    // MARK: Inputs

    let line: LogLine
    let showTimestamp: Bool
    let showContainerBadge: Bool
    let searchQuery: String

    // MARK: Body

    public var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if showTimestamp, let ts = line.timestamp {
                Text(ts)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 200, alignment: .leading)
                    .lineLimit(1)
            }

            if showContainerBadge {
                Text(line.containerName)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.secondary)
            }

            contentText
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .contextMenu {
            Button("Copy Line") { copyLine() }
            Button("Copy with Context") { copyWithContext() }
        }
    }

    // MARK: Private

    @ViewBuilder
    private var contentText: some View {
        if !searchQuery.isEmpty {
            highlightedText(line.content, query: searchQuery)
        } else {
            Text(line.content)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(severityColor)
        }
    }

    private var severityColor: Color {
        line.severity?.color ?? .primary
    }

    private func highlightedText(_ text: String, query: String) -> some View {
        var attributed = AttributedString(text)
        let queryLower = query.lowercased()
        let textLower = text.lowercased()
        if let range = textLower.range(of: queryLower),
           let attrRange = Range(range, in: attributed) {
            attributed[attrRange].backgroundColor = .yellow.withAlphaComponent(0.5)
            attributed[attrRange].foregroundColor = .black
        }
        return Text(attributed)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(severityColor)
    }

    private func copyLine() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line.content, forType: .string)
    }

    private func copyWithContext() {
        var parts: [String] = []
        if let ts = line.timestamp { parts.append(ts) }
        parts.append("[\(line.containerName)]")
        parts.append(line.content)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(parts.joined(separator: " "), forType: .string)
    }
}

