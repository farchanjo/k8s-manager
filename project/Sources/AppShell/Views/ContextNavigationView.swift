// Views/ContextNavigationView.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states)

import SwiftUI
import ContextNavigation

// MARK: - ContextNavigationView

/// Root view for the context navigation vertical slice.
///
/// Presents the sidebar read model: pinned contexts above the recents window.
/// Three-state rendering follows ADR-0031: idle and loading share a single
/// progress indicator; success shows pinned and recent contexts; failure shows
/// an inline error with a retry affordance.
@MainActor
public struct ContextNavigationView: View {

    @State private var viewModel = ContextNavigationViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Contexts")
                .task { await viewModel.loadActiveContext() }
        }
    }

    // MARK: Private views

    @ViewBuilder
    private var content: some View {
        switch viewModel.sidebar {
        case .idle, .loading:
            loadingView
        case .failure(let error):
            errorView(error)
        case .success(let model):
            sidebarList(model)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading active context...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Context Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Retry") {
                Task { await viewModel.loadActiveContext() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func sidebarList(_ model: SidebarReadModel) -> some View {
        List {
            if !model.pinned.isEmpty {
                pinnedSection(model.pinned)
            }
            if !model.recents.isEmpty {
                recentsSection(model.recents)
            }
            if model.pinned.isEmpty && model.recents.isEmpty {
                emptyRow
            }
        }
    }

    private func pinnedSection(_ pinned: [PinnedContext]) -> some View {
        Section("Pinned") {
            ForEach(pinned, id: \.contextId) { pin in
                pinnedRow(pin)
            }
        }
    }

    private func pinnedRow(_ pin: PinnedContext) -> some View {
        HStack {
            Image(systemName: "pin.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.contextId.rawValue).font(.headline)
                Text("Pinned: \(pin.pinnedAtRFC3339)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func recentsSection(_ recents: [RecentContextEntry]) -> some View {
        Section("Recent") {
            ForEach(recents, id: \.contextId) { entry in
                recentRow(entry)
            }
        }
    }

    private func recentRow(_ entry: RecentContextEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).font(.headline)
                Text("Last used: \(entry.lastUsedRFC3339)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("×\(entry.useCount)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var emptyRow: some View {
        Text("No contexts yet.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
    }
}
