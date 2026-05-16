// Views/Editor/ValidationErrorPane.swift — app_shell bounded context
// DDD role: View — bottom pane listing parse/lint errors (Onda 3)
// ADR ref: ADR-0030 (diagnostics panel — line jump support)

import SwiftUI

// MARK: - ValidationErrorPane

/// Bottom pane listing client-side `ValidationError` items.
///
/// Each row shows the severity icon, line/column reference, and message.
/// Tapping a row emits a line-jump callback so the caller can scroll
/// the `CodeEditor` cursor to the relevant position.
public struct ValidationErrorPane: View {

    let errors: [ValidationError]
    var onJumpToLine: ((Int) -> Void)?

    public init(errors: [ValidationError], onJumpToLine: ((Int) -> Void)? = nil) {
        self.errors = errors
        self.onJumpToLine = onJumpToLine
    }

    public var body: some View {
        VStack(spacing: 0) {
            paneHeader
            Divider()
            errorList
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Private views

    private var paneHeader: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text("\(errors.count) \(errors.count == 1 ? "issue" : "issues")")
                .font(.caption.bold())
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var errorList: some View {
        List(errors) { error in
            Button(action: { onJumpToLine?(error.line) }) {
                errorRow(error)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel(for: error))
            .accessibilityHint("Double-tap to jump to this line in the editor")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func errorRow(_ error: ValidationError) -> some View {
        HStack(spacing: 8) {
            severityIcon(error.severity)

            lineRef(error)

            Text(error.message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private func severityIcon(_ severity: ValidationError.Severity) -> some View {
        Group {
            switch severity {
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .imageScale(.small)
        .accessibilityHidden(true)
    }

    private func lineRef(_ error: ValidationError) -> some View {
        Group {
            if let col = error.column {
                Text("L\(error.line):C\(col)")
            } else {
                Text("L\(error.line)")
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .frame(width: 52, alignment: .leading)
    }

    private func accessibilityLabel(for error: ValidationError) -> String {
        let sev = error.severity == .error ? "Error" : "Warning"
        let loc = error.column.map { "line \(error.line), column \($0)" } ?? "line \(error.line)"
        return "\(sev) on \(loc): \(error.message)"
    }
}
