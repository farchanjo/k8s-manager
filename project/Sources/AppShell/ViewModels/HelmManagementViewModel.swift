// ViewModels/HelmManagementViewModel.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states),
//          ADR-0015 (Helm native phased), ADR-0046 (rollback lease mutex)

import Foundation
import Dependencies
import Logging
import HelmManagement
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.helm_management")

// MARK: - HelmManagementViewModel

/// View model for the Helm management screen.
///
/// Owned by `HelmManagementView`. Drives release listing, per-release history
/// loading, and rollback orchestration (lease acquisition → SSA apply).
/// All mutations happen on the `MainActor` so SwiftUI observation coalesces
/// updates without data races.
@Observable
@MainActor
public final class HelmManagementViewModel {

    // MARK: State

    /// Lifecycle state of the releases list load operation.
    public var releases: AsyncResource<[Release]> = .idle

    /// Per-release history load state, keyed by `Release.id` string.
    public var history: [String: AsyncResource<[ReleaseHistoryEntry]>] = [:]

    /// Release currently selected in the list for history detail display.
    public var selectedRelease: Release?

    /// Non-nil while a rollback is in progress (success or failure pending).
    public var rollbackInProgress: Bool = false

    /// Error surfaced by the most recent rollback attempt, if any.
    public var rollbackError: Error?

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.helmReleaseStore) private var releaseStore

    @ObservationIgnored
    @Dependency(\.rollbackLease) private var leasePort

    @ObservationIgnored
    @Dependency(\.serverSideApply) private var applyPort

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads all Helm releases across all namespaces for the active cluster.
    ///
    /// Resets `releases` to `.loading` before the network call and sets it to
    /// `.success` or `.failure` upon completion.
    public func loadReleases() async {
        releases = .loading
        log.info("loadReleases start")
        do {
            let clusterId = ClusterId(UUID().uuidString)
            let list = try await releaseStore.listReleases(clusterId: clusterId, namespace: nil)
            log.info("loadReleases OK — count=\(list.count)")
            releases = .success(list)
        } catch {
            log.error("loadReleases FAILED — \(error)")
            releases = .failure(error)
        }
    }

    /// Loads the revision history for the given release.
    ///
    /// Groups all stored revisions for (name, namespace) and projects them into
    /// `ReleaseHistoryEntry` values. Keyed by `release.id` in `history`.
    ///
    /// - Parameter release: The release whose revision history is requested.
    public func loadHistory(for release: Release) async {
        let key = release.id.uuidString
        history[key] = .loading
        log.info("loadHistory start release=\(release.name) ns=\(release.namespace)")
        do {
            let clusterId = ClusterId(UUID().uuidString)
            let all = try await releaseStore.listReleases(
                clusterId: clusterId,
                namespace: release.namespace
            )
            let entries = all
                .filter { $0.name == release.name }
                .sorted { $0.version > $1.version }
                .map { makeEntry(from: $0) }
            log.info("loadHistory OK release=\(release.name) revisions=\(entries.count)")
            history[key] = .success(entries)
        } catch {
            log.error("loadHistory FAILED release=\(release.name) — \(error)")
            history[key] = .failure(error)
        }
    }

    /// Initiates a rollback of `release` to the specified `revision`.
    ///
    /// Protocol per ADR-0046: acquire rollback Lease → apply stored manifest
    /// via Server-Side Apply → release Lease. Errors are surfaced through
    /// `rollbackError` and rendered by the view.
    ///
    /// - Parameters:
    ///   - release: The current head release to roll back.
    ///   - revision: The target revision number to restore.
    public func rollback(release: Release, to revision: Int) async {
        rollbackInProgress = true
        rollbackError = nil
        log.info("rollback start release=\(release.name) target=\(revision)")
        do {
            try await performRollback(release: release, toRevision: revision)
            log.info("rollback OK release=\(release.name) target=\(revision)")
            await loadReleases()
        } catch {
            log.error("rollback FAILED release=\(release.name) — \(error)")
            rollbackError = error
        }
        rollbackInProgress = false
    }

    // MARK: Private helpers

    /// Acquires lease, applies manifest, releases lease.
    private func performRollback(release: Release, toRevision: Int) async throws {
        let clusterId = ClusterId(UUID().uuidString)
        let holderIdentity = "k8smanager-local-\(ProcessInfo.processInfo.processName)"
        let lease = try await leasePort.acquireLease(
            releaseName: release.name,
            namespace: release.namespace,
            holderIdentity: holderIdentity,
            clusterId: clusterId
        )
        defer {
            Task {
                try? await leasePort.releaseLease(lease, clusterId: clusterId)
            }
        }
        log.info("rollback lease acquired release=\(release.name) holder=\(holderIdentity)")
        _ = try await applyPort.apply(
            manifestYAML: release.manifestYAML,
            namespace: release.namespace,
            clusterId: clusterId,
            force: false
        )
    }

    /// Projects a `Release` aggregate into a `ReleaseHistoryEntry` read model.
    private func makeEntry(from release: Release) -> ReleaseHistoryEntry {
        ReleaseHistoryEntry(
            revision: release.version,
            deployedAtRFC3339: release.modifiedAtRFC3339,
            status: release.status,
            chartVersion: release.chart.version,
            appVersion: release.chart.appVersion,
            description: release.info.description,
            supersededAtRFC3339: nil
        )
    }
}
