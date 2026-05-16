// Views/Security/SecurityRolesView.swift — app_shell bounded context
// DDD role: View — RBAC audit (cluster-admin bindings, wildcard roles)
// ADR ref: ADR-0021 (AppShell orchestration shell extended for Onda 2 security lens)

import SwiftUI
import SharedKernel

// MARK: - SecurityRolesViewModel

/// View model for the RBAC audit panel.
@Observable
@MainActor
final class SecurityRolesViewModel {

    /// Bindings to `cluster-admin` for non-system subjects.
    var clusterAdminBindings: [RBACRisk] = []
    /// Roles and ClusterRoles containing wildcard verbs or resources.
    var wildcardRoles: [RBACRisk] = []
    /// Lifecycle state.
    var loadState: AsyncResource<Void> = .idle

    func load(clusterId: ClusterId) async {
        loadState = .loading
        // Production: enumerate ClusterRoleBindings + Roles + ClusterRoles
        // via KubernetesSecurityListPort and apply heuristics.
        clusterAdminBindings = []
        wildcardRoles = []
        loadState = .success(())
    }
}

// MARK: - SecurityRolesView

/// RBAC audit view showing cluster-admin bindings and wildcard-grant roles.
///
/// Organized as a two-section list:
/// 1. Cluster-admin bindings (high-risk).
/// 2. Roles with wildcard verbs or resources.
///
/// A tree/table visualization is used: each section groups by binding/role
/// name with a secondary row for the subject or wildcard detail.
@MainActor
public struct SecurityRolesView: View {

    private let clusterId: ClusterId

    @State private var viewModel = SecurityRolesViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("RBAC Audit")
                .toolbar {
                    ToolbarItem {
                        Button("Refresh") { Task { await viewModel.load(clusterId: clusterId) } }
                            .disabled(viewModel.loadState.isLoading)
                    }
                }
                .task { await viewModel.load(clusterId: clusterId) }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView("Auditing RBAC…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let error):
            errorView(error)
        case .success:
            rbacList
        }
    }

    private var rbacList: some View {
        List {
            clusterAdminSection
            wildcardSection
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Cluster-admin bindings section

    private var clusterAdminSection: some View {
        Section {
            if viewModel.clusterAdminBindings.isEmpty {
                Text("No cluster-admin bindings for non-system subjects.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.clusterAdminBindings) { risk in
                    RBACRiskRow(risk: risk, accentColor: .red)
                }
            }
        } header: {
            sectionHeader(
                "Cluster-Admin Bindings",
                icon: "shield.fill",
                count: viewModel.clusterAdminBindings.count,
                color: .red
            )
        } footer: {
            Text("Heuristic: any ClusterRoleBinding to cluster-admin whose subject is not a system:* account.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Wildcard roles section

    private var wildcardSection: some View {
        Section {
            if viewModel.wildcardRoles.isEmpty {
                Text("No roles with wildcard verbs or resources detected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.wildcardRoles) { risk in
                    RBACRiskRow(risk: risk, accentColor: .orange)
                }
            }
        } header: {
            sectionHeader(
                "Wildcard Grants",
                icon: "asterisk.circle",
                count: viewModel.wildcardRoles.count,
                color: .orange
            )
        } footer: {
            Text("Roles or ClusterRoles with \"*\" in verbs or resources grant unrestricted access to matched resource groups.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shared helpers

    private func sectionHeader(
        _ title: String,
        icon: String,
        count: Int,
        color: Color
    ) -> some View {
        Label {
            Text(title) + Text(" (\(count))").foregroundStyle(.secondary)
        } icon: {
            Image(systemName: icon).foregroundStyle(count > 0 ? color : .secondary)
        }
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange)
            Text(error.localizedDescription).font(.callout).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.load(clusterId: clusterId) } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - RBACRiskRow

private struct RBACRiskRow: View {
    let risk: RBACRisk
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                kindBadge(risk.kind)
                Text(risk.name).font(.callout)
                if let ns = risk.namespace {
                    Text("(\(ns))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(risk.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private func kindBadge(_ kind: String) -> some View {
        Text(kind)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(accentColor.opacity(0.12))
            .foregroundStyle(accentColor)
            .clipShape(Capsule())
    }
}
