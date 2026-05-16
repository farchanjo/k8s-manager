// Views/LLMProviderView.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI)

import SwiftUI
import LLMProvider

// MARK: - LLMProviderView

/// Root view for the LLM provider settings vertical slice.
///
/// Renders the flat list of configured provider profiles with kind icon,
/// alias, model id, and capability badges. Three-state rendering follows
/// ADR-0031: idle/loading share a progress indicator; success shows the list;
/// failure shows an inline error with a retry affordance.
@MainActor
public struct LLMProviderView: View {

    @State private var viewModel: LLMProviderViewModel

    public init(viewModel: LLMProviderViewModel = LLMProviderViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("LLM Providers")
                .toolbar { addProviderButton }
                .task { await viewModel.loadProviders() }
        }
    }

    // MARK: Private views

    @ViewBuilder
    private var content: some View {
        switch viewModel.providers {
        case .idle, .loading:
            loadingView
        case .failure(let error):
            errorView(error)
        case .success(let model):
            providerList(model)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading providers...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .font(.body)
            Button("Retry") {
                Task { await viewModel.loadProviders() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func providerList(_ model: ProviderListReadModel) -> some View {
        List(model.rows) { row in
            providerRow(row)
                .listRowBackground(
                    viewModel.selectedProviderId == row.id
                        ? Color.accentColor.opacity(0.1)
                        : Color.clear
                )
                .onTapGesture { viewModel.selectProvider(row) }
        }
    }

    private func providerRow(_ row: ProviderListReadModel.Row) -> some View {
        HStack(spacing: 12) {
            kindIcon(for: row.kind)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.displayName).font(.headline)
                Text(row.modelId).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            capabilityBadges(for: row)
        }
        .padding(.vertical, 4)
    }

    private func kindIcon(for kind: ProviderKind) -> some View {
        Image(systemName: systemImage(for: kind))
            .font(.title2)
            .foregroundStyle(tint(for: kind))
            .frame(width: 32)
    }

    @ViewBuilder
    private func capabilityBadges(for row: ProviderListReadModel.Row) -> some View {
        if row.lastVerifiedAtRFC3339 != nil {
            Text("verified")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        } else {
            Text("unverified")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }

    @ToolbarContentBuilder
    private var addProviderButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                // Deferred: add-provider flow not yet implemented
            } label: {
                Label("Add Provider", systemImage: "plus")
            }
        }
    }

    // MARK: Helpers

    private func systemImage(for kind: ProviderKind) -> String {
        switch kind {
        case .anthropic: return "a.circle.fill"
        case .openai: return "o.circle.fill"
        case .openaiCompatible: return "server.rack"
        }
    }

    private func tint(for kind: ProviderKind) -> Color {
        switch kind {
        case .anthropic: return .orange
        case .openai: return .mint
        case .openaiCompatible: return .blue
        }
    }
}
