// ViewModels/ApplicationsViewModel.swift — app_shell bounded context
// DDD role: ViewModel — Applications cluster-scope list
// ADR ref: ADR-0067 (applications cluster-scope view — Helm releases + GitOps extension hooks)

import Foundation
import Dependencies
import Logging
import HelmManagement
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.applications")

// MARK: - ApplicationsViewModel

/// View model for the Applications cluster-scope view.
///
/// Reads Helm releases from ``HelmReleaseStorePort``, applies the active
/// namespace filter, and exposes a sorted ``ApplicationsViewState`` for
/// ``ApplicationsView``. All mutations are `@MainActor`-isolated.
///
/// Row actions call ``openHelmDetail(row:clusterId:)`` which issues an
/// `openTab` command to ``OpenTabsPort`` with the existing `helmRelease` tab kind
/// (ADR-0067 §"Row action: navigate to Helm release detail").
@MainActor
@Observable
public final class ApplicationsViewModel {

    // MARK: - Observed state

    /// Lifecycle state wrapping the current ``ApplicationsViewState``.
    public var viewState: AsyncResource<ApplicationsViewState> = .idle

    /// Sort order applied to the release list.
    public var sortOrder: ApplicationSortOrder = .nameAscending

    /// Namespace filter; `nil` means all namespaces.
    public var namespaceFilter: String?

    // MARK: - Dependencies

    @ObservationIgnored
    @Dependency(\.helmReleaseStore) private var releaseStore

    @ObservationIgnored
    @Dependency(\.openTabs) private var openTabs

    @ObservationIgnored
    private let toastEmitter: any ToastEmitterPort

    // MARK: - Init

    /// Creates a view model.
    ///
    /// - Parameter toastEmitter: Port used to surface mapped failure-mode toasts (ADR-0041).
    ///   Defaults to `NoOpToastEmitter` in preview and test contexts.
    public init(toastEmitter: any ToastEmitterPort = NoOpToastEmitter()) {
        self.toastEmitter = toastEmitter
    }

    // MARK: - Intents

    /// Loads Helm releases for `clusterId` and builds the view state.
    ///
    /// - Parameter clusterId: Active cluster context identifier.
    public func start(clusterId: ClusterId) async {
        viewState = .loading
        log.info("start clusterId=\(clusterId.rawValue)")
        do {
            let releases = try await releaseStore.listReleases(
                clusterId: clusterId,
                namespace: namespaceFilter
            )
            let state = buildState(from: releases)
            viewState = .success(state)
            log.info("start OK count=\(state.releases.count)")
        } catch {
            log.error("start FAILED \(error)")
            viewState = .failure(error)
            await emitMappedToast(for: error)
        }
    }

    /// Reloads using the stored `namespaceFilter`.
    ///
    /// - Parameter clusterId: Active cluster context identifier.
    public func reload(clusterId: ClusterId) async {
        await start(clusterId: clusterId)
    }

    /// Opens the Helm release detail tab for `row`.
    ///
    /// Navigates to the existing `helmRelease` tab kind per ADR-0067 §"Row action".
    ///
    /// - Parameters:
    ///   - row: The selected ``ApplicationRow``.
    ///   - clusterId: Active cluster context identifier.
    public func openHelmDetail(row: ApplicationRow, clusterId: ClusterId) async {
        log.info("openHelmDetail release=\(row.name) ns=\(row.namespace)")
        let tab = DocumentTab.helmRelease(
            clusterId: clusterId,
            releaseName: row.name,
            namespace: row.namespace
        )
        await openTabs.openTab(tab)
    }

    /// Applies `newOrder` and re-sorts without a network round-trip.
    ///
    /// - Parameters:
    ///   - newOrder: The desired ``ApplicationSortOrder``.
    ///   - clusterId: Active cluster context identifier, used to reload if needed.
    public func applySort(_ newOrder: ApplicationSortOrder, clusterId: ClusterId) async {
        sortOrder = newOrder
        guard let current = viewState.value else {
            await start(clusterId: clusterId)
            return
        }
        let sorted = ApplicationsViewState(
            releases: sortedRows(current.releases, by: newOrder),
            namespaceFilter: current.namespaceFilter,
            sortOrder: newOrder,
            argocdEnabled: current.argocdEnabled,
            fluxEnabled: current.fluxEnabled
        )
        viewState = .success(sorted)
    }

    // MARK: - Private

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

    private func buildState(from releases: [Release]) -> ApplicationsViewState {
        // Exclude superseded revisions — keep only the latest per (name, namespace).
        let deduped = deduplicateReleases(releases)
        // Project to rows and apply sort.
        let rows = deduped
            .filter { $0.status != .superseded }
            .map { ApplicationRow(from: $0) }
        let sorted = sortedRows(rows, by: sortOrder)
        return ApplicationsViewState(
            releases: sorted,
            namespaceFilter: namespaceFilter,
            sortOrder: sortOrder,
            argocdEnabled: false,
            fluxEnabled: false
        )
    }

    private func deduplicateReleases(_ releases: [Release]) -> [Release] {
        var latestMap: [String: Release] = [:]
        for release in releases {
            let key = "\(release.namespace)/\(release.name)"
            if let existing = latestMap[key] {
                if release.version > existing.version {
                    latestMap[key] = release
                }
            } else {
                latestMap[key] = release
            }
        }
        return Array(latestMap.values)
    }

    private func sortedRows(
        _ rows: [ApplicationRow],
        by order: ApplicationSortOrder
    ) -> [ApplicationRow] {
        switch order {
        case .nameAscending:
            return rows.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .nameDescending:
            return rows.sorted { $0.name.localizedCompare($1.name) == .orderedDescending }
        case .chartAscending:
            return rows.sorted { $0.chartName.localizedCompare($1.chartName) == .orderedAscending }
        case .chartDescending:
            return rows.sorted { $0.chartName.localizedCompare($1.chartName) == .orderedDescending }
        case .namespaceAscending:
            return rows.sorted { $0.namespace.localizedCompare($1.namespace) == .orderedAscending }
        case .updatedDescending:
            return rows.sorted { $0.updatedRFC3339 > $1.updatedRFC3339 }
        }
    }
}
