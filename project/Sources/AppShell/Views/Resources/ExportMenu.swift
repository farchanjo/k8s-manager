// Views/Resources/ExportMenu.swift — app_shell bounded context
// DDD role: View — toolbar export menu for CSV list export
// ADR ref: ADR-0060 (resource list export CSV and YAML)

import SwiftUI

// MARK: - ExportMenu

/// Toolbar `Menu` button that triggers CSV list export via `NSSavePanel`.
///
/// Placed immediately to the right of the item-count badge in the list toolbar.
/// Hidden when the list is empty or still loading.
///
/// Usage (inside a `toolbar {}` modifier):
/// ```swift
/// ToolbarItem(placement: .primaryAction) {
///     ExportMenu(
///         kind: "Pod",
///         clusterDisplayName: "prod-aks",
///         rows: viewModel.filteredRows.map { row in
///             ResourceListRow(values: [row.name, row.namespace, row.phase.rawValue,
///                                     "\(row.readyContainers)/\(row.totalContainers)",
///                                     "\(row.restartCount)", row.nodeName, row.age])
///         },
///         isHidden: viewModel.filteredRows.isEmpty
///     )
/// }
/// ```
public struct ExportMenu: View {

    private let kind: String
    private let clusterDisplayName: String
    private let rows: [ResourceListRow]
    private let isHidden: Bool

    @State private var isExporting = false

    /// Creates an export menu.
    ///
    /// - Parameters:
    ///   - kind: Kubernetes kind string.
    ///   - clusterDisplayName: Cluster name for the filename template.
    ///   - rows: Already-filtered, sorted rows at export time.
    ///   - isHidden: When `true` the menu is not rendered (e.g., list is empty or loading).
    public init(
        kind: String,
        clusterDisplayName: String = "cluster",
        rows: [ResourceListRow],
        isHidden: Bool = false
    ) {
        self.kind = kind
        self.clusterDisplayName = clusterDisplayName
        self.rows = rows
        self.isHidden = isHidden
    }

    public var body: some View {
        if !isHidden {
            Menu {
                Button {
                    exportCSV(addBOM: false)
                } label: {
                    Label("Export as CSV\u{2026}", systemImage: "tablecells")
                }
                Button {
                    exportCSV(addBOM: true)
                } label: {
                    Label("Export as CSV (Excel)\u{2026}", systemImage: "tablecells.badge.ellipsis")
                }
            } label: {
                Label("Export", systemImage: "arrow.down.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(isExporting)
            .help("Export list as CSV")
        }
    }

    // MARK: Private

    private func exportCSV(addBOM: Bool) {
        let config = KindExportConfig.config(forKind: kind)
        let service = ListExportService()
        let ts = ISO8601DateFormatter().string(from: .now)
        guard let data = try? service.csvData(
            from: rows,
            config: config,
            addBOM: addBOM,
            refreshTimestamp: ts
        ) else { return }

        let filename = CSVFilenameTemplate.filename(
            kind: kind,
            clusterDisplayName: clusterDisplayName
        )
        saveFile(data: data, suggestedName: filename, contentType: "public.comma-separated-values-text")
    }

    private func saveFile(data: Data, suggestedName: String, contentType: String) {
        isExporting = true
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        panel.begin { response in
            defer { isExporting = false }
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

// ExportMenuContainer has been removed per ADR-0074 Change E.
// Export functionality is now accessible via RowActionMenu(exportContext:) —
// pass an ExportContext with the filtered row list when constructing RowActionMenu.
