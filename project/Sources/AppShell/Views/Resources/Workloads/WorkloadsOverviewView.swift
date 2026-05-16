// Views/Resources/Workloads/WorkloadsOverviewView.swift — app_shell bounded context
// DDD role: View — Workloads aggregated dashboard (Onda 2)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import Charts
import SharedKernel

// MARK: - WorkloadSummary

/// Aggregated workload counts fetched from the cluster.
public struct WorkloadSummary: Sendable {
    public let runningPods: Int
    public let pendingPods: Int
    public let failedPods: Int
    public let succeededPods: Int
    public let deploymentCount: Int
    public let healthyDeployments: Int
    public let degradedDeployments: Int
    public let topRestartingPods: [RestartEntry]

    public static let empty = WorkloadSummary(
        runningPods: 0, pendingPods: 0, failedPods: 0, succeededPods: 0,
        deploymentCount: 0, healthyDeployments: 0, degradedDeployments: 0,
        topRestartingPods: []
    )

    public init(
        runningPods: Int, pendingPods: Int, failedPods: Int, succeededPods: Int,
        deploymentCount: Int, healthyDeployments: Int, degradedDeployments: Int,
        topRestartingPods: [RestartEntry]
    ) {
        self.runningPods = runningPods; self.pendingPods = pendingPods
        self.failedPods = failedPods; self.succeededPods = succeededPods
        self.deploymentCount = deploymentCount
        self.healthyDeployments = healthyDeployments
        self.degradedDeployments = degradedDeployments
        self.topRestartingPods = topRestartingPods
    }
}

/// Entry in the top-restarting pods list.
public struct RestartEntry: Identifiable, Sendable {
    public let id: String
    public let podName: String
    public let namespace: String
    public let restartCount: Int
}

// MARK: - PodPhaseSlice (Charts data)

private struct PodPhaseSlice: Identifiable {
    let id = UUID()
    let phase: String
    let count: Int
    let color: Color

    var isVisible: Bool { count > 0 }
}

// MARK: - WorkloadsOverviewView

/// Aggregated dashboard for all workload kinds.
///
/// Shows:
/// - Pod status distribution (pie chart via Swift Charts)
/// - Deployment health badges
/// - Top-5 restarting pods
///
/// Data is derived from the existing Pods + Deployments view models
/// loaded independently to reuse the same port.
public struct WorkloadsOverviewView: View {

    public let clusterId: ClusterId

    @State private var summary: WorkloadSummary = .empty
    @State private var isLoading = false
    @State private var loadError: Error?

    @State private var podsVM = PodsListViewModel()
    @State private var deploymentsVM = DeploymentsListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    podStatusCard
                    deploymentHealthCard
                }
                topRestartingPodsCard
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadSummary() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadSummary() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Workloads Overview")
                    .font(.title2.bold())
                Text("Cluster: \(clusterId.rawValue)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoading { ProgressView().controlSize(.small) }
        }
    }

    private var podStatusCard: some View {
        GroupBox("Pod Status") {
            podPieChart
                .frame(height: 200)
            podStatusLegend
        }
    }

    private var podPieChart: some View {
        let slices = makePodSlices()
        let visibleSlices = slices.filter(\.isVisible)
        return Chart(visibleSlices) { slice in
            SectorMark(
                angle: .value("Count", slice.count),
                innerRadius: .ratio(0.55),
                angularInset: 2
            )
            .foregroundStyle(slice.color)
            .annotation(position: .overlay) {
                if slice.count > 0 {
                    Text("\(slice.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var podStatusLegend: some View {
        HStack(spacing: 16) {
            legendItem(color: .green, label: "Running", count: summary.runningPods)
            legendItem(color: .yellow, label: "Pending", count: summary.pendingPods)
            legendItem(color: .red, label: "Failed", count: summary.failedPods)
            legendItem(color: .blue, label: "Succeeded", count: summary.succeededPods)
        }
        .font(.caption)
        .padding(.top, 8)
    }

    private func legendItem(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label): \(count)").foregroundStyle(.secondary)
        }
    }

    private var deploymentHealthCard: some View {
        GroupBox("Deployment Health") {
            VStack(alignment: .leading, spacing: 12) {
                healthRow(
                    icon: "checkmark.circle.fill", color: .green,
                    label: "Healthy", count: summary.healthyDeployments
                )
                healthRow(
                    icon: "exclamationmark.triangle.fill", color: .orange,
                    label: "Degraded", count: summary.degradedDeployments
                )
                Divider()
                Text("Total: \(summary.deploymentCount) deployments")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }

    private func healthRow(icon: String, color: Color, label: String, count: Int) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            Text(label).foregroundStyle(.primary)
            Spacer()
            Text("\(count)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(count > 0 ? color : .secondary)
        }
    }

    private var topRestartingPodsCard: some View {
        GroupBox("Top Restarting Pods") {
            if summary.topRestartingPods.isEmpty {
                Text("No restart events recorded")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                restartTable
            }
        }
    }

    private var restartTable: some View {
        VStack(spacing: 0) {
            restartHeader
            Divider()
            ForEach(summary.topRestartingPods) { entry in
                restartRow(entry)
                Divider()
            }
        }
    }

    private var restartHeader: some View {
        HStack {
            Text("Pod").font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Text("Namespace").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text("Restarts").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private func restartRow(_ entry: RestartEntry) -> some View {
        HStack {
            Text(entry.podName).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.namespace).font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text("\(entry.restartCount)").font(.callout.monospacedDigit()).foregroundStyle(.red).frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    // MARK: Data loading

    private func loadSummary() async {
        isLoading = true
        loadError = nil
        async let podsLoad: Void = podsVM.start(clusterId: clusterId, namespace: nil)
        async let deploymentsLoad: Void = deploymentsVM.start(clusterId: clusterId, namespace: nil)
        _ = await (podsLoad, deploymentsLoad)
        summary = buildSummary()
        isLoading = false
    }

    private func buildSummary() -> WorkloadSummary {
        let pods = podsVM.rows
        let running = pods.filter { $0.phase == .running }.count
        let pending = pods.filter { $0.phase == .pending }.count
        let failed = pods.filter { $0.phase == .failed }.count
        let succeeded = pods.filter { $0.phase == .succeeded }.count
        let topRestarting = Array(
            pods.sorted { $0.restartCount > $1.restartCount }
                .prefix(5)
                .map { RestartEntry(id: $0.id, podName: $0.name, namespace: $0.namespace, restartCount: $0.restartCount) }
        )
        let deps = deploymentsVM.rows
        let healthy = deps.filter { $0.available > 0 }.count
        let degraded = deps.filter { $0.available == 0 }.count
        return WorkloadSummary(
            runningPods: running, pendingPods: pending,
            failedPods: failed, succeededPods: succeeded,
            deploymentCount: deps.count,
            healthyDeployments: healthy, degradedDeployments: degraded,
            topRestartingPods: topRestarting
        )
    }

    private func makePodSlices() -> [PodPhaseSlice] {
        [
            PodPhaseSlice(phase: "Running", count: summary.runningPods, color: .green),
            PodPhaseSlice(phase: "Pending", count: summary.pendingPods, color: .yellow),
            PodPhaseSlice(phase: "Failed", count: summary.failedPods, color: .red),
            PodPhaseSlice(phase: "Succeeded", count: summary.succeededPods, color: .blue),
        ]
    }
}
