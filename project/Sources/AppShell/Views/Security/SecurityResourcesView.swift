// Views/Security/SecurityResourcesView.swift — app_shell bounded context
// DDD role: View — privileged and exposed resource audit
// ADR ref: ADR-0021 (AppShell orchestration shell extended for Onda 2 security lens)

import SwiftUI
import SharedKernel

// MARK: - SecurityResourcesViewModel

/// View model for the privileged and exposed resources audit.
@Observable
@MainActor
final class SecurityResourcesViewModel {

    /// Pods flagged as privileged (hostNetwork, hostPID, privileged securityContext).
    var privilegedPods: [PrivilegedPodRisk] = []
    /// Services with external exposure (LoadBalancer or NodePort).
    var exposedServices: [ExposedService] = []
    /// Pods running as root or without runAsNonRoot enforcement.
    var rootPods: [PrivilegedPodRisk] = []
    /// Lifecycle state.
    var loadState: AsyncResource<Void> = .idle

    func load(clusterId: ClusterId) async {
        loadState = .loading
        // Production: query pods, services via KubernetesSecurityListPort.
        // Placeholder empty lists so views render configured empty states.
        privilegedPods = []
        exposedServices = []
        rootPods = []
        loadState = .success(())
    }
}

// MARK: - SecurityResourcesView

/// Audit view for privileged pods, exposed services, and root-running pods.
///
/// Each section displays a list with relevant risk flags. All data is read-only.
@MainActor
public struct SecurityResourcesView: View {

    private let clusterId: ClusterId

    @State private var viewModel = SecurityResourcesViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Resource Risks")
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
            ProgressView("Auditing resources…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let error):
            errorView(error)
        case .success:
            auditList
        }
    }

    private var auditList: some View {
        List {
            privilegedPodsSection
            exposedServicesSection
            rootPodsSection
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Privileged pods section

    private var privilegedPodsSection: some View {
        Section {
            if viewModel.privilegedPods.isEmpty {
                Text("No privileged pods detected.").foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.privilegedPods) { pod in
                    PrivilegedPodRow(risk: pod)
                }
            }
        } header: {
            sectionHeader(
                "Privileged Pods",
                icon: "exclamationmark.shield",
                count: viewModel.privilegedPods.count
            )
        }
    }

    // MARK: - Exposed services section

    private var exposedServicesSection: some View {
        Section {
            if viewModel.exposedServices.isEmpty {
                Text("No externally exposed services detected.").foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.exposedServices) { svc in
                    ExposedServiceRow(service: svc)
                }
            }
        } header: {
            sectionHeader(
                "Exposed Services",
                icon: "antenna.radiowaves.left.and.right",
                count: viewModel.exposedServices.count
            )
        }
    }

    // MARK: - Root pods section

    private var rootPodsSection: some View {
        Section {
            if viewModel.rootPods.isEmpty {
                Text("No root-running pods detected.").foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.rootPods) { pod in
                    RootPodRow(risk: pod)
                }
            }
        } header: {
            sectionHeader(
                "Pods Running as Root",
                icon: "person.badge.key",
                count: viewModel.rootPods.count
            )
        }
    }

    // MARK: - Shared helpers

    private func sectionHeader(_ title: String, icon: String, count: Int) -> some View {
        Label {
            Text(title) + Text(" (\(count))").foregroundStyle(.secondary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(count > 0 ? .orange : .secondary)
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

// MARK: - Sub-rows

private struct PrivilegedPodRow: View {
    let risk: PrivilegedPodRisk

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(risk.podName).font(.callout)
            HStack(spacing: 8) {
                Text(risk.namespace).font(.caption).foregroundStyle(.secondary)
                flagBadge("Privileged", active: risk.isPrivileged)
                flagBadge("HostNetwork", active: risk.hasHostNetwork)
                flagBadge("HostPID", active: risk.hasHostPID)
            }
        }
        .padding(.vertical, 2)
    }

    private func flagBadge(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(active ? Color.red.opacity(0.15) : Color.clear)
            .foregroundStyle(active ? .red : .secondary)
            .clipShape(Capsule())
    }
}

private struct ExposedServiceRow: View {
    let service: ExposedService

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(service.serviceName).font(.callout)
                Text(service.namespace).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(service.serviceType)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        }
    }
}

private struct RootPodRow: View {
    let risk: PrivilegedPodRisk

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(risk.podName).font(.callout)
                Text(risk.namespace).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "person.fill.questionmark")
                .foregroundStyle(.red)
        }
    }
}
