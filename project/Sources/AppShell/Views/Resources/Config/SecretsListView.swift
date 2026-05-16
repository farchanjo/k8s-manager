// Views/Resources/Config/SecretsListView.swift — app_shell bounded context
// DDD role: View
// ADR ref: ADR-0050 (resource navigation taxonomy), ADR-0063 (secret reveal/hide)

import SwiftUI
import SharedKernel
import ResourceBrowser

// MARK: - SecretsListView

/// Table view listing Kubernetes Secrets for a given cluster and namespace.
///
/// Supports row selection, namespace picker, refresh, and per-row context menus
/// (Edit YAML, Describe, Reveal Data, Delete). Binary secret values are masked.
@MainActor
public struct SecretsListView: View {

    let clusterId: ClusterId

    @State private var viewModel = SecretsListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        Group {
            switch viewModel.loadState {
            case .idle, .loading:
                loadingView
            case .failure(let error):
                errorView(error)
            case .success:
                tableView
            }
        }
        .navigationTitle("Secrets")
        .toolbar { toolbarContent }
        .task { await viewModel.start(clusterId: clusterId, namespace: nil) }
        .alert("Delete Secret?", isPresented: $viewModel.showDeleteConfirm) {
            Button("Delete", role: .destructive) { viewModel.pendingDeleteRow = nil }
            Button("Cancel", role: .cancel) { viewModel.pendingDeleteRow = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $viewModel.showRevealSheet) {
            if let row = viewModel.revealRow {
                SecretRevealSheet(row: row, clusterId: clusterId)
            }
        }
    }

    // MARK: Private views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading Secrets\u{2026}").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(error.localizedDescription).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.reload(clusterId: clusterId) } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tableView: some View {
        Table(viewModel.rows, selection: $viewModel.selectedId) {
            TableColumn("Name", value: \.name)
            TableColumn("Namespace", value: \.namespace)
            TableColumn("Type", value: \.type)
            TableColumn("Data") { row in
                Text("\(row.dataCount)").monospacedDigit()
            }
            TableColumn("Age", value: \.age)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let row = viewModel.rows.first(where: { ids.contains($0.id) }) {
                rowContextMenu(row)
            }
        }
    }

    @ViewBuilder
    private func rowContextMenu(_ row: SecretRow) -> some View {
        let actions = RowActionMenuBuilder.actions(for: RowActionContext(
            kind: "Secret", name: row.name, namespace: row.namespace, family: .config
        ))
        ForEach(actions) { action in
            if action.id == "delete" {
                Divider()
                Button("Delete\u{2026}", role: .destructive) { viewModel.requestDelete(row) }
            } else if action.id == "reveal-data" {
                Button("Reveal Data") { viewModel.revealData(row) }
            } else {
                Button(action.label) {}
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await viewModel.reload(clusterId: clusterId) } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }
}

// MARK: - SecretRevealSheet

/// Sheet presenting Secret data keys with per-key reveal/hide affordance.
///
/// All values start masked. Each key has a `SecretRevealButton` that reveals
/// the decoded value inline. For `kubernetes.io/dockerconfigjson`, clicking
/// reveal on the `.dockerconfigjson` key shows a `DockerConfigInspector`.
/// Each reveal writes an audit entry via `SecretRevealAuditPort`.
@MainActor
private struct SecretRevealSheet: View {

    let row: SecretRow
    let clusterId: ClusterId

    @State private var sheetViewModel: SecretRevealSheetViewModel

    @Environment(\.dismiss) private var dismiss

    init(row: SecretRow, clusterId: ClusterId) {
        self.row = row
        self.clusterId = clusterId
        _sheetViewModel = State(initialValue: SecretRevealSheetViewModel(row: row, clusterId: clusterId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerBar
            Divider()
            dataSection
            Spacer()
        }
        .padding()
        .frame(minWidth: 560, minHeight: 400)
    }

    private var headerBar: some View {
        HStack {
            Label("Secret \u{2014} \(row.name)", systemImage: "lock.fill")
                .font(.headline)
            Spacer()
            Button("Done") { dismiss() }
        }
    }

    private var dataSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                metaSummary
                Divider().padding(.vertical, 8)
                keyRows
            }
        }
    }

    private var metaSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Namespace: \(row.namespace)")
                .font(.caption).foregroundStyle(.secondary)
            Text("Type: \(row.type)")
                .font(.caption).foregroundStyle(.secondary)
            Text("Keys: \(row.dataCount)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var keyRows: some View {
        if sheetViewModel.keyStates.isEmpty {
            Text("No data keys available.")
                .font(.caption).foregroundStyle(.tertiary).italic()
        } else {
            ForEach(sheetViewModel.orderedKeys, id: \.self) { key in
                keyRow(key: key)
                Divider().opacity(0.4)
            }
        }
    }

    private func keyRow(key: String) -> some View {
        let state = sheetViewModel.keyStates[key] ?? .masked
        return HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .frame(minWidth: 140, alignment: .leading)
                .lineLimit(1)
            Spacer()
            valueDisplay(key: key, state: state)
            SecretRevealButton(
                keyName: key,
                isRevealed: state.isRevealed,
                onReveal: { Task { await sheetViewModel.reveal(key: key) } },
                onHide: { Task { await sheetViewModel.hide(key: key) } }
            )
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func valueDisplay(key: String, state: KeyRevealState) -> some View {
        switch state {
        case .masked:
            Text("\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        case .revealed(let text):
            if row.type == "kubernetes.io/dockerconfigjson" && key == ".dockerconfigjson" {
                dockerConfigView(rawValue: text)
            } else {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
        case .error(let msg):
            Text("Error: \(msg)")
                .font(.caption2).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func dockerConfigView(rawValue: String) -> some View {
        let parseResult = sheetViewModel.parsedDockerConfig(rawValue: rawValue)
        DockerConfigInspector(
            config: parseResult.config,
            parseError: parseResult.error,
            revealedPasswords: Binding(
                get: { sheetViewModel.revealedDockerPasswords },
                set: { sheetViewModel.revealedDockerPasswords = $0 }
            ),
            onRevealPassword: { registry in
                Task { await sheetViewModel.revealDockerPassword(registry: registry) }
            },
            onHidePassword: { registry in
                Task { await sheetViewModel.hideDockerPassword(registry: registry) }
            }
        )
    }
}
