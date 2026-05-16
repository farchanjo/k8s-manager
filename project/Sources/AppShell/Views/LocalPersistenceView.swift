// Views/LocalPersistenceView.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states)

import SwiftUI
import LocalPersistence

// MARK: - LocalPersistenceView

/// Root view for the `local_persistence` vertical slice.
///
/// Presents three independent sections — Store, Audit Chain, and Keychain
/// Entries — each with its own three-state loading lifecycle (idle/loading,
/// success, failure) following ADR-0031. Unwired adapters surface as
/// inline errors with Retry affordances so the shell remains navigable
/// during incremental adapter wiring.
@MainActor
public struct LocalPersistenceView: View {

    @State private var viewModel: LocalPersistenceViewModel

    public init(viewModel: LocalPersistenceViewModel = LocalPersistenceViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            List {
                storeSection
                auditChainSection
                keychainSection
            }
            .navigationTitle("Local Data")
            .task {
                await viewModel.loadStoreInfo()
                await viewModel.loadAuditChainState()
                await viewModel.loadKeychainEntries()
            }
        }
    }

    // MARK: Store section

    private var storeSection: some View {
        Section("Store") {
            switch viewModel.store {
            case .idle, .loading:
                loadingRow(label: "Loading store info…")
            case .failure(let error):
                errorRow(error) { Task { await viewModel.loadStoreInfo() } }
            case .success(let s):
                storeRows(s)
            }
        }
    }

    @ViewBuilder
    private func storeRows(_ store: PersistenceStore) -> some View {
        labeledRow(title: "Path", value: store.storageFilePath)
        labeledRow(title: "Schema version", value: "v\(store.schemaVersion)")
        labeledRow(title: "Journal mode", value: store.journalMode.uppercased())
    }

    // MARK: Audit chain section

    private var auditChainSection: some View {
        Section("Audit Chain") {
            switch viewModel.auditChainState {
            case .idle, .loading:
                loadingRow(label: "Verifying chain state…")
            case .failure(let error):
                errorRow(error) { Task { await viewModel.loadAuditChainState() } }
            case .success(let state):
                auditChainRow(state)
            }
        }
    }

    @ViewBuilder
    private func auditChainRow(_ state: AuditChainState) -> some View {
        HStack {
            Text("Integrity")
            Spacer()
            auditStateBadge(state)
        }
        if case .corrupt(let id, let reason) = state {
            labeledRow(title: "Failing entry", value: id.uuidString)
            labeledRow(title: "Reason", value: reason)
        }
        if case .reseeded(let id) = state {
            labeledRow(title: "New genesis entry", value: id.uuidString)
        }
        if case .paused(let reason) = state {
            labeledRow(title: "Reason", value: reason)
        }
    }

    private func auditStateBadge(_ state: AuditChainState) -> some View {
        let (label, color) = badgeConfig(for: state)
        return Text(label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private func badgeConfig(for state: AuditChainState) -> (String, Color) {
        switch state {
        case .intact:          return ("Intact", .green)
        case .paused:          return ("Paused", .orange)
        case .corrupt:         return ("Corrupt", .red)
        case .reseeded:        return ("Reseeded", .blue)
        }
    }

    // MARK: Keychain section

    private var keychainSection: some View {
        Section("Keychain Entries") {
            switch viewModel.keychainEntries {
            case .idle, .loading:
                loadingRow(label: "Loading keychain entries…")
            case .failure(let error):
                errorRow(error) { Task { await viewModel.loadKeychainEntries() } }
            case .success(let entries):
                keychainRows(entries)
            }
        }
    }

    @ViewBuilder
    private func keychainRows(_ entries: [KeychainEntry]) -> some View {
        let namespaces: [KeychainServiceNamespace] = [.llm, .oidc, .azure, .audit]
        ForEach(namespaces, id: \.rawValue) { ns in
            let count = entries.filter { $0.namespace == ns }.count
            labeledRow(title: ns.displayName, value: "\(count) item(s)")
        }
        labeledRow(title: "Total", value: "\(entries.count) item(s)")
    }

    // MARK: Shared sub-views

    private func loadingRow(label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func labeledRow(title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func errorRow(_ error: Error, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - KeychainServiceNamespace + display

private extension KeychainServiceNamespace {
    var displayName: String {
        switch self {
        case .llm:   return "LLM"
        case .oidc:  return "OIDC"
        case .azure: return "Azure"
        case .audit: return "Audit"
        }
    }
}
