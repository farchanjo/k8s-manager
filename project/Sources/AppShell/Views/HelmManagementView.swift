// Views/HelmManagementView.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0015 (Helm native phased)

import SwiftUI
import HelmManagement

// MARK: - HelmManagementView

/// Root view for the Helm management vertical slice.
///
/// Presents a list of deployed Helm releases with status badges. Selecting a
/// release reveals its revision history alongside per-revision Rollback buttons.
/// Three-state rendering follows ADR-0031: idle and loading share a progress
/// indicator; success shows content; failure shows an inline error with retry.
@MainActor
public struct HelmManagementView: View {

    @State private var viewModel: HelmManagementViewModel

    public init(viewModel: HelmManagementViewModel = HelmManagementViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Helm Releases")
                .task { await viewModel.loadReleases() }
        }
    }

    // MARK: Private views

    @ViewBuilder
    private var content: some View {
        switch viewModel.releases {
        case .idle, .loading:
            loadingView
        case .failure(let error):
            errorView(error) { await viewModel.loadReleases() }
        case .success(let list):
            releaseList(list)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading releases...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error, retry: @escaping () async -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .font(.body)
            Button("Retry") {
                Task { await retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func releaseList(_ list: [Release]) -> some View {
        HSplitView {
            List(list, id: \.id, selection: Binding(
                get: { viewModel.selectedRelease },
                set: { release in
                    viewModel.selectedRelease = release
                    if let release {
                        Task { await viewModel.loadHistory(for: release) }
                    }
                }
            )) { release in
                releaseRow(release)
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 380, maxHeight: .infinity)
            historyPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func releaseRow(_ release: Release) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(release.name).font(.headline)
                Text("\(release.chart.name) \(release.chart.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("ns: \(release.namespace)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge(release.status)
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: ReleaseStatus) -> some View {
        Text(status.rawValue)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(badgeColor(for: status))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private func badgeColor(for status: ReleaseStatus) -> Color {
        switch status {
        case .deployed:                     return .green
        case .failed:                       return .red
        case .uninstalled, .superseded:     return .gray
        case .pendingInstall, .pendingUpgrade, .pendingRollback: return .orange
        }
    }

    // MARK: History panel

    @ViewBuilder
    private var historyPanel: some View {
        if let release = viewModel.selectedRelease {
            historyContent(for: release)
        } else {
            ContentUnavailableView(
                "Select a release",
                systemImage: "shippingbox",
                description: Text("Pick a release to view its revision history")
            )
        }
    }

    @ViewBuilder
    private func historyContent(for release: Release) -> some View {
        let key = release.id.uuidString
        switch viewModel.history[key] {
        case .none, .some(.idle), .some(.loading):
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .some(.failure(let error)):
            errorView(error) { await viewModel.loadHistory(for: release) }
        case .some(.success(let entries)):
            historyList(entries, release: release)
        }
    }

    private func historyList(
        _ entries: [ReleaseHistoryEntry],
        release: Release
    ) -> some View {
        List(entries, id: \.revision) { entry in
            historyRow(entry, release: release)
        }
        .navigationTitle("\(release.name) — History")
        .overlay(rollbackOverlay)
    }

    private func historyRow(
        _ entry: ReleaseHistoryEntry,
        release: Release
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rev \(entry.revision)  •  \(entry.chartVersion)")
                    .font(.headline)
                Text(entry.deployedAtRFC3339)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            statusBadge(entry.status)
            Button("Rollback") {
                Task { await viewModel.rollback(release: release, to: entry.revision) }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.rollbackInProgress)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var rollbackOverlay: some View {
        if viewModel.rollbackInProgress {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Rolling back…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
