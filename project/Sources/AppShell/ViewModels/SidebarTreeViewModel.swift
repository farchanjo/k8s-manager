// ViewModels/SidebarTreeViewModel.swift — app_shell bounded context
// DDD role: ViewModel
// ADR ref: ADR-0050 (sidebar taxonomy + tab system), ADR-0051 (cluster strip),
//          ADR-0052 (CRD dynamic sidebar nodes)

import Foundation
import SwiftUI
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.sidebar_tree")

// MARK: - Dependency keys (fallback if parallel agent has not wired these yet)
//
// `ClusterStripDependencyKey` lives in `Actors/ClusterStripActor.swift` so it
// is public and shared with `ClusterStripView`/`ClusterStripViewModel` and the
// composition root. Keeping it in one place prevents the two-actor split bug
// where the cluster strip would broadcast to its own actor and the sidebar
// would silently observe a different one.

public enum OpenTabsDependencyKey: DependencyKey {
    public static let liveValue: any OpenTabsPort = UnimplementedOpenTabsPort()
    public static let testValue: any OpenTabsPort = NoOpOpenTabsPort()
}

// MARK: - OpenTabsPort

/// Port for the open-tabs subsystem, consumed by `SidebarTreeViewModel` and
/// other view models that need to open or observe tabs.
///
/// The full `OpenTabsActor` implementation is defined in a parallel delivery.
/// This protocol provides a compile-time surface so `SidebarTreeViewModel`
/// can be tested without the actor being live.
public protocol OpenTabsPort: Sendable {
    /// Opens (or focuses) the given `DocumentTab`.
    func openTab(_ tab: DocumentTab) async

    /// Returns an `AsyncStream` that emits the current state immediately and on
    /// every subsequent mutation. Used by `SidebarTreeViewModel` to derive
    /// `selectedNode` from the active tab (ADR-0070).
    func stateStream() -> AsyncStream<OpenTabsSnapshot>
}

private struct UnimplementedOpenTabsPort: OpenTabsPort {
    func openTab(_ tab: DocumentTab) async {
        preconditionFailure("OpenTabsPort not injected — wire a real implementation at the composition root")
    }

    func stateStream() -> AsyncStream<OpenTabsSnapshot> {
        AsyncStream { _ in }
    }
}

private struct NoOpOpenTabsPort: OpenTabsPort {
    func openTab(_ tab: DocumentTab) async {}

    func stateStream() -> AsyncStream<OpenTabsSnapshot> {
        AsyncStream { _ in }
    }
}

extension DependencyValues {
    /// Access key for the `OpenTabsPort`.
    ///
    /// Wire the live `OpenTabsActor` at the composition root.
    /// Tests may supply `NoOpOpenTabsPort` or a spy double via `withDependencies`.
    public var openTabs: any OpenTabsPort {
        get { self[OpenTabsDependencyKey.self] }
        set { self[OpenTabsDependencyKey.self] = newValue }
    }
}

// MARK: - SidebarTreeViewModel

/// View model for the Lens-style hierarchical sidebar tree.
///
/// Reads the active cluster from `ClusterStripActor` and opens tabs via
/// `OpenTabsPort` when the operator activates a `SidebarNode`.
///
/// All mutations are isolated to `MainActor` so SwiftUI `@Observable`
/// observation coalesces view updates without data races.
@MainActor
@Observable
public final class SidebarTreeViewModel {

    // MARK: Published state

    /// Display name of the active cluster, or `nil` when none is selected.
    public var activeClusterName: String?

    /// Stable identifier of the active cluster.
    public var activeClusterId: ClusterId?

    /// Authentication provider of the active cluster (ADR-0051 §"Per-cluster
    /// sidebar tree" — drives the provider section header).
    public var activeProviderKind: ClusterProviderKind?

    /// Whether the active cluster's connection is established.
    public var isConnected: Bool = false

    /// `true` until the first `ClusterStripActor` snapshot arrives. Drives
    /// the cold-load skeleton (ADR-0031 §"Skeleton loaders — Sidebar").
    public var hasReceivedSnapshot: Bool = false

    /// The sidebar node currently selected (drives `List` highlight).
    public var selectedNode: SidebarNode?

    /// Set of group nodes that are currently expanded.
    public var expandedGroups: Set<SidebarNode> = []

    /// Dynamic CRD group nodes derived from the latest `CRDCatalog` snapshot.
    ///
    /// Keyed by API group string; values are `customResourceKind` leaf nodes.
    public var crdGroups: [String: [SidebarNode]] = [:]

    /// Sorted API group keys for the custom resources section.
    public var crdGroupKeys: [String] { crdGroups.keys.sorted() }

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.clusterStrip) private var clusterStrip

    @ObservationIgnored
    @Dependency(\.openTabs) private var openTabs

    @ObservationIgnored
    @Dependency(\.crdDiscovery) private var crdDiscovery

    // MARK: Init

    public init() {}

    // MARK: - Lifecycle

    /// Subscribes to the `ClusterStripActor` state stream and keeps
    /// `activeClusterName` / `activeClusterId` up to date.
    ///
    /// Also subscribes to `OpenTabsPort.stateStream()` so `selectedNode`
    /// is derived from the active tab — preventing sidebar–tab desync when
    /// tabs are opened or closed from outside the sidebar (ADR-0070).
    ///
    /// Call once from a `.task {}` modifier on the owning view.
    public func start() async {
        log.info("SidebarTreeViewModel.start — subscribing to cluster strip + open tabs")
        async let _ = subscribeToOpenTabs()
        for await snapshot in clusterStrip.stateStream() {
            apply(snapshot: snapshot)
            if let cid = snapshot.activeClusterId {
                await startCRDWatch(clusterId: cid)
            }
        }
    }

    /// Subscribes to `OpenTabsPort.stateStream()` and keeps `selectedNode`
    /// mirrored from `activeTabId` — implementing the derived-selection
    /// invariant from ADR-0070.
    ///
    /// Also expands the parent group node when the derived leaf is inside a
    /// collapsed section, so the highlighted row is visible in the `OutlineGroup`
    /// (SwiftUI's OutlineGroup manages its own expansion state; the view model
    /// tracks `expandedGroups` and `SidebarTreeView` must observe it to keep
    /// the disclosure triangles consistent with the selection).
    private func subscribeToOpenTabs() async {
        for await snapshot in openTabs.stateStream() {
            guard let activeId = snapshot.activeTabId,
                  let activeTab = snapshot.tabs.first(where: { $0.id == activeId })
            else { continue }
            guard let derived = SidebarNode.from(documentTab: activeTab) else { continue }
            if derived != selectedNode {
                selectedNode = derived
                expandParentIfNeeded(for: derived)
                log.debug("selectedNode derived from activeTab=\(activeTab.title)")
            }
        }
    }

    /// Ensures the parent group for `node` is marked expanded so the row is
    /// visible when the OutlineGroup re-renders. Only expands — never collapses —
    /// to avoid disrupting an operator who has manually collapsed a section.
    private func expandParentIfNeeded(for node: SidebarNode) {
        let parent = SidebarNode.parentGroup(of: node)
        if let parent, !expandedGroups.contains(parent) {
            expandedGroups.insert(parent)
        }
    }

    // MARK: - Private — CRD catalog watch

    /// Watches the CRD catalog for `clusterId` and updates `crdGroups`.
    ///
    /// Silently swallows discovery errors so the sidebar remains functional
    /// even when the service account lacks CRD list permission.
    private func startCRDWatch(clusterId: ClusterId) async {
        do {
            let catalog = try await crdDiscovery.discoverCRDs(clusterId: clusterId)
            applyCatalog(catalog)
        } catch {
            log.warning("CRD initial discovery failed — \(error)")
        }
    }

    private func applyCatalog(_ catalog: CRDCatalog) {
        let grouped = catalog.groupedByAPIGroup()
        crdGroups = grouped.mapValues { entries in
            entries.map { .customResourceKind($0.id) }
        }
        log.info("CRD catalog applied — \(crdGroups.keys.count) group(s)")
    }

    // MARK: - Intents

    /// Activates `node`, opening (or focusing) the corresponding `DocumentTab`.
    ///
    /// Silently no-ops when no cluster is active or the node has no tab mapping.
    public func activate(_ node: SidebarNode) async {
        selectedNode = node
        guard let clusterId = activeClusterId else {
            log.debug("activate ignored — no active cluster")
            return
        }
        guard let tab = node.toDocumentTab(clusterId: clusterId) else {
            log.debug("activate — node \(node.id) is a group header, toggling expansion")
            toggleExpansion(of: node)
            return
        }
        log.info("activate node=\(node.id) tab=\(tab.title) cluster=\(clusterId.rawValue)")
        await openTabs.openTab(tab)
    }

    /// Toggles the expansion state of a group node.
    public func toggleExpansion(of node: SidebarNode) {
        if expandedGroups.contains(node) {
            expandedGroups.remove(node)
        } else {
            expandedGroups.insert(node)
        }
    }

    // MARK: - Private

    private func apply(snapshot: ClusterStripSnapshot) {
        hasReceivedSnapshot = true
        activeClusterId = snapshot.activeClusterId
        if let cid = snapshot.activeClusterId,
           let pin = snapshot.pins.first(where: { $0.clusterId == cid }) {
            activeClusterName = pin.displayName
            activeProviderKind = pin.providerKind
            isConnected = true
        } else {
            let fallbackPin = snapshot.pins.first
            activeClusterName = fallbackPin?.displayName
            activeProviderKind = fallbackPin?.providerKind
            isConnected = false
        }
    }
}
