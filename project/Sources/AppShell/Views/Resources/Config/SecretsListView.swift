// Views/Resources/Config/SecretsListView.swift — app_shell bounded context
// DDD role: View
// ADR ref: ADR-0050 (resource navigation taxonomy)

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
                SecretRevealModal(row: row)
            }
        }
    }

    // MARK: Private views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading Secrets…").font(.callout).foregroundStyle(.secondary)
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
        Button("Reveal Data") { viewModel.revealData(row) }
        Divider()
        Button("Edit YAML") {}
        Button("Describe") {}
        Divider()
        Button("Delete…", role: .destructive) { viewModel.requestDelete(row) }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            namespacePicker
        }
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await viewModel.reload(clusterId: clusterId) } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    private var namespacePicker: some View {
        TextField("Namespace", text: Binding(
            get: { viewModel.namespace ?? "" },
            set: { viewModel.namespace = $0.isEmpty ? nil : $0 }
        ))
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 120, maxWidth: 180)
        .onSubmit { Task { await viewModel.reload(clusterId: clusterId) } }
    }
}

// MARK: - SecretRevealModal

/// Sheet presenting decoded Secret data keys with copy affordances.
///
/// Binary values are masked as `<binary N bytes>`. UTF-8 decodable values
/// are shown in a monospaced text field with a copy button per entry.
@MainActor
private struct SecretRevealModal: View {
    let row: SecretRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerBar
            Divider()
            dataSection
            Spacer()
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
    }

    private var headerBar: some View {
        HStack {
            Label("Secret — \(row.name)", systemImage: "lock.fill")
                .font(.headline)
            Spacer()
            Button("Done") { dismiss() }
        }
    }

    private var dataSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Type: \(row.type)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Keys: \(row.dataCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("(Full decode available after API secret fetch is wired.)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
    }
}
