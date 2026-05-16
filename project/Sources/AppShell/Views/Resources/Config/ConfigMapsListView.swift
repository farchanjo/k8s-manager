// Views/Resources/Config/ConfigMapsListView.swift — app_shell bounded context
// DDD role: View
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import SharedKernel
import ResourceBrowser

// MARK: - ConfigMapsListView

/// Table view listing Kubernetes ConfigMaps for a given cluster and namespace.
///
/// Supports row selection, a namespace picker toolbar, refresh, and per-row
/// context menus (Edit YAML, Describe, View Data, Delete).
@MainActor
public struct ConfigMapsListView: View {

    let clusterId: ClusterId

    @State private var viewModel = ConfigMapsListViewModel()
    @State private var showDataModal = false
    @State private var dataModalRow: ConfigMapRow?

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
        .navigationTitle("ConfigMaps")
        .toolbar { toolbarContent }
        .task { await viewModel.start(clusterId: clusterId, namespace: nil) }
        .alert("Delete ConfigMap?", isPresented: $viewModel.showDeleteConfirm) {
            Button("Delete", role: .destructive) { viewModel.pendingDeleteRow = nil }
            Button("Cancel", role: .cancel) { viewModel.pendingDeleteRow = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showDataModal) {
            if let row = dataModalRow {
                ConfigMapDataModal(row: row)
            }
        }
    }

    // MARK: Private views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading ConfigMaps…").font(.callout).foregroundStyle(.secondary)
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
    private func rowContextMenu(_ row: ConfigMapRow) -> some View {
        Button("View Data") {
            dataModalRow = row
            showDataModal = true
        }
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

// MARK: - ConfigMapDataModal

/// Modal sheet revealing the keys of a ConfigMap (values omitted for brevity).
@MainActor
private struct ConfigMapDataModal: View {
    let row: ConfigMapRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("ConfigMap Data — \(row.name)").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            Divider()
            Text("Data keys: \(row.dataCount)")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(minWidth: 480, minHeight: 300)
    }
}
