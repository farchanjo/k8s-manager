// Views/StatusBar/StatusBarView.swift — app_shell bounded context
// DDD role: View (presentation layer)
// ADR ref: ADR-0051 (status bar — 24 pt bottom chrome strip)

import SwiftUI

// MARK: - StatusBarView

/// 24 pt bottom chrome strip displaying active cluster telemetry.
///
/// Layout (left → right):
/// - Connection dot + cluster name + server version.
/// - Divider.
/// - CPU % chip + Mem % chip.
/// - Divider.
/// - Watch-stream badge + error-count badge.
/// - Trailing spacer.
/// - Support button.
///
/// The 30 s refresh loop is attached via `.task`. Error counting observes the
/// shared `ToastStackViewModel` to record `.error` severity cards emitted in
/// the current session.
public struct StatusBarView: View {

    @State private var viewModel = StatusBarViewModel()

    /// The shared toast view model from the scene root; used to observe error toasts.
    var toastViewModel: ToastStackViewModel

    public init(toastViewModel: ToastStackViewModel) {
        self.toastViewModel = toastViewModel
    }

    public var body: some View {
        HStack(spacing: 16) {
            clusterIdentity
            Divider().frame(height: 12)
            resourceUtilization
            Divider().frame(height: 12)
            watchAndErrors
            Spacer()
            supportButton
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
        .font(.caption)
        .task { await viewModel.start() }
        .task { await pruneErrorsLoop() }
        .onChange(of: toastViewModel.activeToasts.count, recordNewErrors)
    }

    // MARK: - Sub-views

    private var clusterIdentity: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.connectionBadge.color)
                .frame(width: 8, height: 8)
            Text(viewModel.clusterName)
                .fontWeight(.medium)
                .lineLimit(1)
            Text(viewModel.serverVersion)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var resourceUtilization: some View {
        HStack(spacing: 12) {
            MetricChip(
                label: "CPU",
                value: viewModel.cpuPercent.map { "\(Int($0))%" } ?? "—"
            )
            MetricChip(
                label: "Mem",
                value: viewModel.memPercent.map { "\(Int($0))%" } ?? "—"
            )
        }
    }

    private var watchAndErrors: some View {
        HStack(spacing: 12) {
            Label("\(viewModel.activeWatchCount)", systemImage: "eye")
                .foregroundStyle(.secondary)
            Label("\(viewModel.errorCount)", systemImage: "exclamationmark.triangle")
                .foregroundStyle(viewModel.errorCount > 0 ? .red : .secondary)
        }
    }

    private var supportButton: some View {
        Button(action: openSupport) {
            HStack(spacing: 4) {
                Image(systemName: "lifepreserver")
                Text("Support")
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Actions

    private func openSupport() {
        guard let url = URL(string: "https://github.com/farchanjo/K8S-Manager/issues") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Error tracking

    /// Scans `toastViewModel.activeToasts` for new `.error` severity cards
    /// and records each one into the view model's ring buffer.
    private func recordNewErrors() {
        for card in toastViewModel.activeToasts where card.severity == .error {
            viewModel.recordError()
        }
    }

    /// Prunes stale error entries every 60 s.
    private func pruneErrorsLoop() async {
        while !Task.isCancelled {
            viewModel.pruneErrors()
            try? await Task.sleep(for: .seconds(60))
        }
    }
}

// MARK: - MetricChip

/// Inline label + value chip for a single resource metric.
private struct MetricChip: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}
