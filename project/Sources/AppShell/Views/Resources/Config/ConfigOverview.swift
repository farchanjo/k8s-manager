// Views/Resources/Config/ConfigOverview.swift — app_shell bounded context
// DDD role: View (aggregate overview card)
// ADR ref: ADR-0050 (resource navigation taxonomy — Config category)

import SwiftUI
import SharedKernel
import Dependencies
import ResourceBrowser

// MARK: - ConfigOverviewViewModel

/// Loads summary counts for all Config-category resource kinds.
@Observable
@MainActor
final class ConfigOverviewViewModel {

    struct KindSummary: Identifiable, Sendable {
        let id: String
        let kind: String
        let systemImage: String
        let count: AsyncResource<Int>
    }

    var summaries: [KindSummary] = Self.emptyKinds

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var resourceList

    func load(clusterId: ClusterId) async {
        await withTaskGroup(of: (String, Int?).self) { group in
            for kind in Self.kindSpecs {
                group.addTask {
                    let count = try? await self.resourceList.list(
                        gvk: kind.gvk, namespace: nil, clusterId: clusterId
                    ).count
                    return (kind.id, count)
                }
            }
            var counts: [String: Int] = [:]
            for await (id, count) in group {
                counts[id] = count
            }
            summaries = Self.kindSpecs.map { spec in
                KindSummary(
                    id: spec.id,
                    kind: spec.displayName,
                    systemImage: spec.systemImage,
                    count: counts[spec.id].map { .success($0) } ?? .failure(ResourceListError.unimplemented)
                )
            }
        }
    }

    private struct KindSpec: Sendable {
        let id: String
        let displayName: String
        let systemImage: String
        let gvk: GroupVersionKind
    }

    private static let kindSpecs: [KindSpec] = [
        KindSpec(id: "configmaps", displayName: "ConfigMaps", systemImage: "doc.plaintext",
                 gvk: .core("ConfigMap")),
        KindSpec(id: "secrets", displayName: "Secrets", systemImage: "lock",
                 gvk: .core("Secret")),
        KindSpec(id: "resourcequotas", displayName: "ResourceQuotas", systemImage: "gauge",
                 gvk: .core("ResourceQuota")),
        KindSpec(id: "limitranges", displayName: "LimitRanges", systemImage: "ruler",
                 gvk: .core("LimitRange")),
        KindSpec(id: "hpas", displayName: "HPAs", systemImage: "arrow.up.arrow.down",
                 gvk: GroupVersionKind(group: "autoscaling", version: "v2", kind: "HorizontalPodAutoscaler")),
        KindSpec(id: "pdbs", displayName: "PodDisruptionBudgets", systemImage: "shield",
                 gvk: GroupVersionKind(group: "policy", version: "v1", kind: "PodDisruptionBudget")),
        KindSpec(id: "priorityclasses", displayName: "PriorityClasses", systemImage: "flag",
                 gvk: GroupVersionKind(group: "scheduling.k8s.io", version: "v1", kind: "PriorityClass")),
        KindSpec(id: "runtimeclasses", displayName: "RuntimeClasses", systemImage: "cpu",
                 gvk: GroupVersionKind(group: "node.k8s.io", version: "v1", kind: "RuntimeClass")),
        KindSpec(id: "leases", displayName: "Leases", systemImage: "clock",
                 gvk: GroupVersionKind(group: "coordination.k8s.io", version: "v1", kind: "Lease")),
        KindSpec(id: "mutatingwebhooks", displayName: "MutatingWebhooks", systemImage: "arrow.triangle.merge",
                 gvk: GroupVersionKind(group: "admissionregistration.k8s.io", version: "v1",
                                       kind: "MutatingWebhookConfiguration")),
        KindSpec(id: "validatingwebhooks", displayName: "ValidatingWebhooks", systemImage: "checkmark.shield",
                 gvk: GroupVersionKind(group: "admissionregistration.k8s.io", version: "v1",
                                       kind: "ValidatingWebhookConfiguration")),
    ]

    private static var emptyKinds: [KindSummary] {
        kindSpecs.map { KindSummary(id: $0.id, kind: $0.displayName,
                                    systemImage: $0.systemImage, count: .idle) }
    }
}

// MARK: - ConfigOverview

/// Aggregate overview showing resource counts for all Config-category kinds.
///
/// Used as the landing tile when the user selects the Config category node
/// in the sidebar tree without choosing a specific kind.
@MainActor
public struct ConfigOverview: View {

    let clusterId: ClusterId
    @State private var viewModel = ConfigOverviewViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                ForEach(viewModel.summaries) { summary in
                    summaryCard(summary)
                }
            }
            .padding()
        }
        .navigationTitle("Config")
        .task { await viewModel.load(clusterId: clusterId) }
    }

    private func summaryCard(_ summary: ConfigOverviewViewModel.KindSummary) -> some View {
        VStack(spacing: 8) {
            Image(systemName: summary.systemImage)
                .font(.title2)
                .foregroundStyle(.accent)
            Text(summary.kind)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            countLabel(summary.count)
        }
        .padding()
        .frame(minWidth: 140, minHeight: 100)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func countLabel(_ resource: AsyncResource<Int>) -> some View {
        switch resource {
        case .idle, .loading:
            ProgressView().controlSize(.small)
        case .success(let count):
            Text("\(count)")
                .font(.title3.bold())
                .monospacedDigit()
        case .failure:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}
