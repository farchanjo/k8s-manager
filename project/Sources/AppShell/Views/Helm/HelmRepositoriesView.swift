// Views/Helm/HelmRepositoriesView.swift — app_shell bounded context
// DDD role: View — configured Helm repositories management (Phase 1 scaffold)
// ADR ref: ADR-0015 §Phase 2 (HTTP/OCI repo CRUD deferred)

import SwiftUI
import SharedKernel

// MARK: - HelmRepositoryRow

/// Display row for a configured Helm repository.
///
/// Phase 1: static in-memory list seeded from known chart museum patterns.
/// Phase 2: materialised from `ChartRepositoryPort.listRepositories`.
public struct HelmRepositoryRow: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let url: String
    public let lastUpdated: String
    public let isOCI: Bool

    public init(id: UUID = UUID(), name: String, url: String, lastUpdated: String, isOCI: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.lastUpdated = lastUpdated
        self.isOCI = isOCI
    }
}

// MARK: - HelmRepositoriesView

/// List of configured Helm chart repositories with Add / Update / Remove actions.
///
/// Phase 1 renders a stub list with the management controls scaffolded.
/// `Add` and `Update` open an `AddRepositorySheet` placeholder.
/// `Remove` pops a confirmation alert before deleting from local state.
public struct HelmRepositoriesView: View {

    public let clusterId: ClusterId

    @State private var rows: [HelmRepositoryRow] = HelmRepositoriesView.stubRows
    @State private var selectedId: HelmRepositoryRow.ID?
    @State private var showAddSheet: Bool = false
    @State private var deletionTarget: HelmRepositoryRow?

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        VStack(spacing: 0) {
            repoToolbar
            Divider()
            repoTable
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddSheet) {
            AddRepositorySheet { newRow in
                rows.append(newRow)
                showAddSheet = false
            }
        }
        .confirmationDialog(
            deletePrompt,
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) { deletionTarget = nil }
        }
    }

    // MARK: Toolbar

    private var repoToolbar: some View {
        HStack(spacing: 8) {
            Text("\(rows.count) repos")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Update All") { updateAll() }
                .buttonStyle(.bordered)
            Button("Add…") { showAddSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: Table

    private var repoTable: some View {
        Table(rows, selection: $selectedId) {
            TableColumn("Name") { row in
                HStack(spacing: 6) {
                    Image(systemName: row.isOCI ? "shippingbox.fill" : "doc.richtext")
                        .foregroundStyle(row.isOCI ? .blue : .secondary)
                        .imageScale(.small)
                    Text(row.name).fontWeight(.medium)
                }
            }
            TableColumn("URL", value: \.url)
            TableColumn("Last Updated") { row in
                Text(row.lastUpdated)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Type") { row in
                Text(row.isOCI ? "OCI" : "HTTP")
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(row.isOCI ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1),
                                in: Capsule())
                    .foregroundStyle(row.isOCI ? .blue : .secondary)
            }
        }
        .contextMenu(forSelectionType: HelmRepositoryRow.ID.self) { ids in
            Button("Update") { updateSelected(ids: ids) }
            Divider()
            Button("Remove", role: .destructive) { beginDelete(ids: ids) }
        }
    }

    // MARK: Actions

    private func updateAll() {
        // Phase 2: call ChartRepositoryPort.updateIndex for each repo.
    }

    private func updateSelected(ids: Set<HelmRepositoryRow.ID>) {
        // Phase 2: call ChartRepositoryPort.updateIndex for selected.
        _ = ids
    }

    private func beginDelete(ids: Set<HelmRepositoryRow.ID>) {
        guard let id = ids.first,
              let row = rows.first(where: { $0.id == id }) else { return }
        deletionTarget = row
    }

    private func confirmDelete() {
        guard let target = deletionTarget else { return }
        rows.removeAll { $0.id == target.id }
        if selectedId == target.id { selectedId = nil }
        deletionTarget = nil
    }

    private var deletePrompt: String {
        if let t = deletionTarget {
            return "Remove '\(t.name)'?"
        }
        return "Remove repository?"
    }

    // MARK: Stub data

    private static let stubRows: [HelmRepositoryRow] = [
        HelmRepositoryRow(
            name: "stable",
            url: "https://charts.helm.sh/stable",
            lastUpdated: "2026-05-10",
            isOCI: false
        ),
        HelmRepositoryRow(
            name: "bitnami",
            url: "oci://registry-1.docker.io/bitnamicharts",
            lastUpdated: "2026-05-15",
            isOCI: true
        ),
        HelmRepositoryRow(
            name: "ingress-nginx",
            url: "https://kubernetes.github.io/ingress-nginx",
            lastUpdated: "2026-05-12",
            isOCI: false
        ),
    ]
}

// MARK: - AddRepositorySheet

/// Sheet for adding a new Helm repository.
///
/// Phase 1: collects name + URL and invokes `onAdd` with a stub `HelmRepositoryRow`.
/// Phase 2: will call `ChartRepositoryPort.addRepository`.
private struct AddRepositorySheet: View {

    let onAdd: (HelmRepositoryRow) -> Void

    @State private var name: String = ""
    @State private var url: String = ""
    @State private var isOCI: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Repository") {
                    TextField("Name (e.g. bitnami)", text: $name)
                    TextField("URL (https:// or oci://)", text: $url)
                    Toggle("OCI Registry", isOn: $isOCI)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Repository")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { commitAdd() }
                        .disabled(name.isEmpty || url.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 200)
    }

    private func commitAdd() {
        let row = HelmRepositoryRow(
            name: name.trimmingCharacters(in: .whitespaces),
            url: url.trimmingCharacters(in: .whitespaces),
            lastUpdated: "just now",
            isOCI: isOCI
        )
        onAdd(row)
    }
}
