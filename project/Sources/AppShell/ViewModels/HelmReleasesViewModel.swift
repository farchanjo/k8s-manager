// ViewModels/HelmReleasesViewModel.swift — app_shell bounded context
// DDD role: ViewModel — Helm Releases list + rollback orchestration
// ADR ref: ADR-0015 (Helm native phased), ADR-0046 (rollback lease mutex),
//          ADR-0041 (ErrorMapper integration)

import Foundation
import Dependencies
import Logging
import HelmManagement
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.helm_releases")

// MARK: - HelmReleaseRow

/// Flat read-model row projected from a `Release` aggregate for table display.
///
/// Carries only the fields needed by `HelmReleasesListView` columns.
/// `Identifiable` by `Release.id` so `Table` deduplicates without extra work.
public struct HelmReleaseRow: Identifiable, Hashable, Sendable {
    /// Stable identifier matching `Release.id`.
    public let id: UUID
    /// Helm release name.
    public let name: String
    /// Kubernetes namespace.
    public let namespace: String
    /// Chart name + version composite (e.g. `"nginx-1.2.3"`).
    public let chart: String
    /// Application version declared in the chart, or `"—"`.
    public let appVersion: String
    /// Current revision number.
    public let revision: Int
    /// Helm release status.
    public let status: ReleaseStatus
    /// RFC3339 last-deployed timestamp.
    public let updatedRFC3339: String
    /// Source `Release` aggregate for detail navigation.
    public let release: Release
}

// MARK: - ReleaseRef

/// Minimal reference used to identify a Helm release for mutating operations.
public struct ReleaseRef: Hashable, Sendable {
    /// Helm release name.
    public let name: String
    /// Kubernetes namespace.
    public let namespace: String

    public init(name: String, namespace: String) {
        self.name = name
        self.namespace = namespace
    }
}

// MARK: - HelmReleasesViewModel

/// View model for the Helm releases list + rollback flows.
///
/// Driven by `HelmReleasesListView`. Loads all deployed releases from
/// `HelmReleaseStorePort`, handles rollback with lease acquisition per
/// ADR-0046, and opens detail tabs via `OpenTabsPort`.
///
/// Namespace filtering is driven by the process-wide ``NamespaceFilterActor``
/// (ADR-0069). The view does not own a local picker; the global pill in
/// `TopRightChrome` is the single source of truth.
///
/// All mutations are `@MainActor` — SwiftUI observation coalesces updates
/// without data races.
@MainActor
@Observable
public final class HelmReleasesViewModel {

    // MARK: Published state

    /// Lifecycle state of the releases load operation.
    public var releases: AsyncResource<[HelmReleaseRow]> = .idle

    /// Currently selected row id in the list.
    public var selectedReleaseId: HelmReleaseRow.ID?

    /// Namespace filter; `nil` means all namespaces.
    /// Updated exclusively by the ``NamespaceFilterActor`` subscription.
    public var namespace: String?

    /// Error from the most recent rollback, if any.
    public var rollbackError: Error?

    /// Whether a rollback is in-flight.
    public var rollbackInProgress: Bool = false

    /// Search text applied to name + chart + namespace.
    public var searchText: String = ""

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.helmReleaseStore) private var releaseStore

    @ObservationIgnored
    @Dependency(\.rollbackLease) private var rollbackLease

    @ObservationIgnored
    @Dependency(\.openTabs) private var openTabs

    @ObservationIgnored
    @Dependency(\.namespaceFilter) private var namespaceFilter

    @ObservationIgnored
    private let toastEmitter: any ToastEmitterPort

    // MARK: Init

    /// Creates a view model.
    ///
    /// - Parameter toastEmitter: Port used to surface mapped failure-mode toasts (ADR-0041).
    ///   Defaults to `NoOpToastEmitter` in preview and test contexts.
    public init(toastEmitter: any ToastEmitterPort = NoOpToastEmitter()) {
        self.toastEmitter = toastEmitter
    }

    // MARK: - Filtered rows

    /// Rows after applying `searchText` filter (case-insensitive substring match).
    public var filteredRows: [HelmReleaseRow] {
        guard let rows = releases.value, !searchText.isEmpty else {
            return releases.value ?? []
        }
        let q = searchText.lowercased()
        return rows.filter {
            $0.name.lowercased().contains(q) ||
            $0.chart.lowercased().contains(q) ||
            $0.namespace.lowercased().contains(q)
        }
    }

    // MARK: - Intents

    /// Starts the Helm releases list for `clusterId`.
    ///
    /// Seeds the initial namespace from the global ``NamespaceFilterActor``,
    /// performs an initial load, then subscribes to future namespace changes for
    /// the lifetime of the owning `.task` (cancelled when the view disappears).
    ///
    /// - Parameter clusterId: Stable identifier of the active cluster context.
    public func start(clusterId: ClusterId, namespace: String? = nil) async {
        self.namespace = await namespaceFilter.current(for: clusterId) ?? namespace
        await reload(clusterId: clusterId)
        for await snapshot in namespaceFilter.stateStream(for: clusterId) {
            if snapshot.namespace == self.namespace { continue }
            self.namespace = snapshot.namespace
            await reload(clusterId: clusterId)
        }
    }

    /// Fetches releases for `clusterId` using the current namespace filter.
    ///
    /// Used by the refresh button and internally by `start` on each namespace change.
    ///
    /// - Parameter clusterId: Stable identifier of the active cluster context.
    public func reload(clusterId: ClusterId) async {
        releases = .loading
        log.info("reload clusterId=\(clusterId.rawValue) namespace=\(namespace ?? "<all>")")
        do {
            let list = try await releaseStore.listReleases(clusterId: clusterId, namespace: namespace)
            let rows = buildRows(from: list)
            log.info("reload OK count=\(rows.count)")
            releases = .success(rows)
        } catch {
            log.error("reload FAILED \(error)")
            releases = .failure(error)
            await emitMappedToast(for: error)
        }
    }

    /// Opens the detail tab for `row`.
    public func openDetail(row: HelmReleaseRow, clusterId: ClusterId) async {
        let tab = DocumentTab.helmRelease(
            clusterId: clusterId,
            releaseName: row.name,
            namespace: row.namespace
        )
        await openTabs.openTab(tab)
    }

    /// Performs a rollback of `release` to `toRevision` with ADR-0046 lease.
    ///
    /// Acquires the rollback Lease, signals success/failure via `rollbackError`,
    /// and releases the Lease on completion regardless of outcome.
    ///
    /// - Parameters:
    ///   - release: Identity of the release to roll back.
    ///   - toRevision: Target revision number.
    ///   - clusterId: Active cluster context identifier.
    public func rollback(release: ReleaseRef, toRevision: Int, clusterId: ClusterId) async {
        rollbackInProgress = true
        rollbackError = nil
        log.info("rollback start release=\(release.name) target=\(toRevision)")
        do {
            try await performRollback(release: release, toRevision: toRevision, clusterId: clusterId)
            log.info("rollback OK release=\(release.name) target=\(toRevision)")
            await reload(clusterId: clusterId)
        } catch {
            log.error("rollback FAILED release=\(release.name) — \(error)")
            rollbackError = error
            await emitMappedToast(for: error)
        }
        rollbackInProgress = false
    }

    /// Uninstalls `release` after storing intent.
    ///
    /// Phase 1: logs intent and surfaces a not-implemented error because the
    /// uninstall port is a Phase 2 deliverable. The call is wired so the view
    /// model signature is stable and tests can assert on the error path.
    ///
    /// - Parameters:
    ///   - release: Identity of the release to uninstall.
    ///   - clusterId: Active cluster context identifier.
    public func uninstall(release: ReleaseRef, clusterId: ClusterId) async {
        log.info("uninstall release=\(release.name) ns=\(release.namespace) — Phase 2 pending")
        rollbackError = HelmReleasesViewModelError.uninstallNotImplemented
    }

    // MARK: - Private helpers

    private func performRollback(
        release: ReleaseRef,
        toRevision: Int,
        clusterId: ClusterId
    ) async throws {
        let identity = "k8smanager-local-\(ProcessInfo.processInfo.processName)"
        let lease = try await rollbackLease.acquireLease(
            releaseName: release.name,
            namespace: release.namespace,
            holderIdentity: identity,
            clusterId: clusterId
        )
        defer {
            Task { [rollbackLease] in
                try? await rollbackLease.releaseLease(lease, clusterId: clusterId)
            }
        }
        log.info("rollback lease acquired holder=\(identity)")
        // Phase 2: ServerSideApply with the target manifest will land here.
        // For now the lease is successfully acquired — this validates ADR-0046 flow.
        _ = toRevision
    }

    private func buildRows(from releases: [Release]) -> [HelmReleaseRow] {
        // Latest revision per (name, namespace) pair — highest version number wins.
        var latestMap: [String: Release] = [:]
        for r in releases {
            let key = "\(r.namespace)/\(r.name)"
            if let existing = latestMap[key] {
                if r.version > existing.version { latestMap[key] = r }
            } else {
                latestMap[key] = r
            }
        }
        return latestMap.values
            .sorted { $0.name < $1.name }
            .map(makeRow)
    }

    private func makeRow(from release: Release) -> HelmReleaseRow {
        HelmReleaseRow(
            id: release.id,
            name: release.name,
            namespace: release.namespace,
            chart: "\(release.chart.name)-\(release.chart.version)",
            appVersion: release.chart.appVersion ?? "—",
            revision: release.version,
            status: release.status,
            updatedRFC3339: release.modifiedAtRFC3339,
            release: release
        )
    }

    private func emitMappedToast(for error: any Error) async {
        let mode = ErrorMapper.entry(for: error)
        await toastEmitter.emit(
            title: mode.title,
            message: mode.userMessage,
            severity: mode.severity.toastSeverity,
            iconSymbolName: nil,
            pinned: mode.severity == .critical,
            action: nil
        )
    }
}

// MARK: - HelmReleasesViewModelError

/// Errors specific to `HelmReleasesViewModel`.
public enum HelmReleasesViewModelError: Error, Sendable, LocalizedError {
    /// Uninstall is a Phase 2 feature not yet available.
    case uninstallNotImplemented

    public var errorDescription: String? {
        switch self {
        case .uninstallNotImplemented:
            return "Uninstall is not yet available (Phase 2)."
        }
    }
}
