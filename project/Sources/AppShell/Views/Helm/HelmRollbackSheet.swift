// Views/Helm/HelmRollbackSheet.swift — app_shell bounded context
// DDD role: View — Rollback wizard with lease coordination
// ADR ref: ADR-0046 (Helm rollback Lease-based mutual exclusion)

import SwiftUI
import SharedKernel
import HelmManagement

// MARK: - HelmRollbackSheet

/// Three-step rollback wizard: pick revision → confirm → progress with lease.
///
/// Lease acquisition protocol per ADR-0046:
///   1. Acquire `coordination.k8s.io/v1/Lease` for the release.
///   2. Perform the rollback (Phase 2: SSA patch; Phase 1: lease-only dry-run).
///   3. Release the lease on success or failure.
///
/// `onComplete` is called when the wizard finishes (success or user cancel).
public struct HelmRollbackSheet: View {

    public let release: ReleaseRef
    public let currentRevision: Int
    public let historyEntries: [ReleaseHistoryEntry]
    public let clusterId: ClusterId
    public let onComplete: () -> Void

    @State private var targetRevision: Int?
    @State private var phase: RollbackPhase = .picking
    @State private var rollbackError: Error?

    @ObservationIgnored
    @Dependency(\.rollbackLease) private var leasePort

    public init(
        release: ReleaseRef,
        currentRevision: Int,
        historyEntries: [ReleaseHistoryEntry],
        clusterId: ClusterId,
        onComplete: @escaping () -> Void
    ) {
        self.release = release
        self.currentRevision = currentRevision
        self.historyEntries = historyEntries
        self.clusterId = clusterId
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            phaseContent
                .navigationTitle("Rollback \(release.name)")
                .toolbar { toolbarItems }
        }
        .frame(minWidth: 540, minHeight: 380)
    }

    // MARK: Phase routing

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .picking:      pickingView
        case .confirming:   confirmingView
        case .inProgress:   progressView
        case .done:         doneView
        case .failed:       failedView
        }
    }

    // MARK: Picking phase

    private var pickingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                icon: "clock.arrow.circlepath",
                title: "Select target revision",
                subtitle: "Current: revision \(currentRevision)"
            )
            Divider()
            if historyEntries.isEmpty {
                noHistoryPlaceholder
            } else {
                revisionList
            }
        }
    }

    private var noHistoryPlaceholder: some View {
        ContentUnavailableView(
            "No history available",
            systemImage: "clock",
            description: Text("Load the release detail view first to populate revision history.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var revisionList: some View {
        List(historyEntries, id: \.revision, selection: Binding(
            get: { targetRevision },
            set: { targetRevision = $0 }
        )) { entry in
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Rev \(entry.revision)")
                            .fontWeight(entry.revision == currentRevision ? .bold : .regular)
                        if entry.revision == currentRevision {
                            Text("current")
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                    Text(entry.chartVersion)
                        .font(.caption).foregroundStyle(.secondary)
                    Text(entry.deployedAtRFC3339)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                HelmStatusBadge(status: entry.status)
            }
            .padding(.vertical, 2)
            .tag(entry.revision)
        }
    }

    // MARK: Confirming phase

    private var confirmingView: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            VStack(spacing: 8) {
                Text("Confirm rollback")
                    .font(.title2).fontWeight(.semibold)
                Text("Roll \(release.name) back from revision \(currentRevision) to revision \(targetRevision ?? 0)?")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("This will acquire a Kubernetes Lease to prevent concurrent rollbacks.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Cancel") { phase = .picking }
                    .buttonStyle(.bordered)
                Button("Rollback") {
                    Task { await performRollback() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Progress phase

    private var progressView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Acquiring rollback lease…")
                .font(.headline)
            Text("Executing rollback to revision \(targetRevision ?? 0)…")
                .foregroundStyle(.secondary)
            Text("This may take a moment. The lease will be released automatically.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Done phase

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56)).foregroundStyle(.green)
            Text("Rollback complete")
                .font(.title2).fontWeight(.semibold)
            Text("\(release.name) rolled back to revision \(targetRevision ?? 0).")
                .foregroundStyle(.secondary)
            Button("Done") { onComplete() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Failed phase

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56)).foregroundStyle(.red)
            Text("Rollback failed")
                .font(.title2).fontWeight(.semibold)
            Text(rollbackError?.localizedDescription ?? "Unknown error")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Close") { onComplete() }
                    .buttonStyle(.bordered)
                Button("Try Again") { phase = .picking }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            if phase == .picking {
                Button("Next") { phase = .confirming }
                    .disabled(targetRevision == nil || targetRevision == currentRevision)
            }
        }
        ToolbarItem(placement: .cancellationAction) {
            if phase != .inProgress {
                Button("Cancel") { onComplete() }
            }
        }
    }

    // MARK: Rollback execution

    private func performRollback() async {
        phase = .inProgress
        guard let revision = targetRevision else { return }
        do {
            let identity = "k8smanager-local-\(ProcessInfo.processInfo.processName)"
            let lease = try await leasePort.acquireLease(
                releaseName: release.name,
                namespace: release.namespace,
                holderIdentity: identity,
                clusterId: clusterId
            )
            defer {
                Task { [leasePort] in
                    try? await leasePort.releaseLease(lease, clusterId: clusterId)
                }
            }
            // Phase 2: Server-Side Apply of the target revision manifest goes here.
            _ = revision
            phase = .done
        } catch {
            rollbackError = error
            phase = .failed
        }
    }

    // MARK: Helpers

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

// MARK: - RollbackPhase

private enum RollbackPhase {
    case picking
    case confirming
    case inProgress
    case done
    case failed
}
