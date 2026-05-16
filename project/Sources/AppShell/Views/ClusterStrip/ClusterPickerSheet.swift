// Views/ClusterStrip/ClusterPickerSheet.swift — app_shell bounded context
// ADR ref: ADR-0051 (cluster picker — pin new contexts from kubeconfig)

import SwiftUI
import Dependencies
import ClusterConnectivity
import SharedKernel

// MARK: - ClusterPickerSheet

/// Modal sheet listing all kubeconfig contexts that are not yet pinned.
///
/// Reads the kubeconfig via `@Dependency(\.kubeconfigLoader)`.
/// Tapping a context row pins it via the injected `onPin` closure and dismisses
/// the sheet. Rows already present in `pinnedIds` are excluded from the list.
public struct ClusterPickerSheet: View {

    // MARK: Input

    var pinnedIds: Set<ClusterId>
    var onPin: (ClusterId, String) async throws -> Void

    // MARK: Private state

    @State private var contexts: [KubeconfigContext] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @Environment(\.dismiss) private var dismiss

    @Dependency(\.kubeconfigLoader) private var kubeconfigLoader

    // MARK: Init

    public init(
        pinnedIds: Set<ClusterId>,
        onPin: @escaping (ClusterId, String) async throws -> Void
    ) {
        self.pinnedIds = pinnedIds
        self.onPin = onPin
    }

    // MARK: Body

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading kubeconfig…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    errorView(error)
                } else {
                    contextList
                }
            }
            .navigationTitle("Pin a Cluster")
            .toolbar { dismissButton }
        }
        .frame(width: 480, height: 400)
        .task { await loadContexts() }
    }

    // MARK: Sub-views

    private var contextList: some View {
        List(unpinnedContexts, id: \.name) { context in
            contextRow(context)
        }
    }

    private func contextRow(_ context: KubeconfigContext) -> some View {
        Button {
            Task {
                let cid = ClusterId(context.cluster)
                try? await onPin(cid, context.name)
                dismiss()
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(context.name).font(.headline)
                Text("Cluster: \(context.cluster)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center)
            Button("Retry") { Task { await loadContexts() } }.buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dismissButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
    }

    // MARK: Data

    private var unpinnedContexts: [KubeconfigContext] {
        contexts.filter { !pinnedIds.contains(ClusterId($0.cluster)) }
    }

    private func loadContexts() async {
        isLoading = true
        loadError = nil
        do {
            let path = KubeconfigPath("~/.kube/config")
            let config = try await kubeconfigLoader.load(from: path)
            contexts = kubeconfigLoader.contexts(in: config)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
