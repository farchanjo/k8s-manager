// Views/Security/SecurityOverviewView.swift — app_shell bounded context
// DDD role: View — security score dashboard (Lens-pattern)
// ADR ref: ADR-0021 (AppShell orchestration shell extended for Onda 2 security lens)

import SwiftUI
import SharedKernel

// MARK: - SecurityOverviewView

/// Security score dashboard presenting the cluster-level risk posture.
///
/// Displays a 0-100 score ring, per-severity finding counts, recent security
/// alerts, Pod Security Standards compliance tiers, and a high-level RBAC
/// overview. All data is read-only; no mutations to cluster state.
@MainActor
public struct SecurityOverviewView: View {

    private let clusterId: ClusterId

    @State private var viewModel: SecurityOverviewViewModel

    public init(clusterId: ClusterId, viewModel: SecurityOverviewViewModel = .init()) {
        self.clusterId = clusterId
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Security Overview")
                .task { await viewModel.start(clusterId: clusterId) }
                .toolbar {
                    ToolbarItem {
                        Button("Refresh") {
                            Task { await viewModel.reload(clusterId: clusterId) }
                        }
                        .disabled(viewModel.loadState.isLoading)
                    }
                }
        }
    }

    // MARK: - Private

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            loadingView
        case .failure(let error):
            errorView(error)
        case .success:
            ScrollView {
                LazyVStack(spacing: 16) {
                    scoreSection
                    findingsSection
                    alertsSection
                    pssSection
                    rbacSection
                }
                .padding()
            }
        }
    }

    // MARK: - Score ring section

    private var scoreSection: some View {
        GroupBox("Security Score") {
            HStack(spacing: 24) {
                ScoreRingView(score: viewModel.score)
                scoreLabels
            }
            .padding(.vertical, 8)
        }
    }

    private var scoreLabels: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(scoreLabel(viewModel.score))
                .font(.title2.bold())
                .foregroundStyle(scoreColor(viewModel.score))
            Text("Based on \(viewModel.findings.total) finding(s) detected.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Findings section

    private var findingsSection: some View {
        GroupBox("Findings") {
            HStack(spacing: 12) {
                SeverityBadge(label: "Critical", count: viewModel.findings.critical, color: .red)
                SeverityBadge(label: "High",     count: viewModel.findings.high,     color: .orange)
                SeverityBadge(label: "Medium",   count: viewModel.findings.medium,   color: .yellow)
                SeverityBadge(label: "Low",      count: viewModel.findings.low,      color: .blue)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Alerts section

    private var alertsSection: some View {
        GroupBox("Recent Alerts (top \(viewModel.topAlerts.count))") {
            if viewModel.topAlerts.isEmpty {
                emptyLabel("No recent security alerts detected.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.topAlerts) { alert in
                        AlertRow(alert: alert)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - PSS section

    private var pssSection: some View {
        let compliance = viewModel.podSecurityCompliance
        return GroupBox("Pod Security Standards Compliance") {
            HStack(spacing: 16) {
                PSSLevelTile(label: "Restricted", count: compliance.restricted, color: .green)
                PSSLevelTile(label: "Baseline",   count: compliance.baseline,   color: .yellow)
                PSSLevelTile(label: "Privileged", count: compliance.privileged,  color: .red)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - RBAC section

    private var rbacSection: some View {
        let overview = viewModel.rbacOverview
        return GroupBox("RBAC Overview") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("ClusterRoleBindings", value: "\(overview.clusterRoleBindingCount)")
                LabeledContent("Over-permissioned (cluster-admin)", value: "\(overview.overPermissionedBindingCount)")
                    .foregroundStyle(overview.overPermissionedBindingCount > 0 ? .red : .primary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Running security audit…").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange)
            Text(error.localizedDescription).font(.callout).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.reload(clusterId: clusterId) } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 80...100: return "Good"
        case 60..<80:  return "Fair"
        case 40..<60:  return "Poor"
        default:       return "Critical"
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80:  return .yellow
        case 40..<60:  return .orange
        default:       return .red
        }
    }
}

// MARK: - ScoreRingView

private struct ScoreRingView: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.2), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.title2.bold().monospacedDigit())
        }
        .frame(width: 80, height: 80)
    }

    private var ringColor: Color {
        switch score {
        case 80...100: return .green
        case 60..<80:  return .yellow
        case 40..<60:  return .orange
        default:       return .red
        }
    }
}

// MARK: - SeverityBadge

private struct SeverityBadge: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(count > 0 ? color : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
        .padding(8)
        .background(color.opacity(count > 0 ? 0.1 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - AlertRow

private struct AlertRow: View {
    let alert: SecurityAlert

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            severityDot
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title).font(.callout)
                if let ref = alert.resource {
                    Text("\(ref.kind.kind)/\(ref.name)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(alert.timestamp)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var severityDot: some View {
        Circle()
            .fill(severityColor(alert.severity))
            .frame(width: 8, height: 8)
            .padding(.top, 4)
    }

    private func severityColor(_ severity: AlertSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .high:     return .orange
        case .medium:   return .yellow
        case .low:      return .blue
        case .info:     return .gray
        }
    }
}

// MARK: - PSSLevelTile

private struct PSSLevelTile: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)").font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
        .padding(8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
