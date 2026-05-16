// ViewModels/SidebarTreeViewModel.swift — app_shell bounded context
// DDD role: ViewModel
// ADR ref: ADR-0050 (sidebar taxonomy + tab system), ADR-0051 (cluster strip)

import Foundation
import SwiftUI
import Dependencies
import Logging
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.sidebar_tree")

// MARK: - Dependency keys (fallback if parallel agent has not wired these yet)

private enum OpenTabsDependencyKey: DependencyKey {
    static let liveValue: any OpenTabsPort = UnimplementedOpenTabsPort()
    static let testValue: any OpenTabsPort = NoOpOpenTabsPort()
}

private enum ClusterStripDependencyKey: DependencyKey {
    static let liveValue: ClusterStripActor = ClusterStripActor()
    static let testValue: ClusterStripActor = ClusterStripActor()
}

// MARK: - OpenTabsPort

/// Minimal port for opening a tab from the sidebar.
///
/// The full `OpenTabsActor` implementation is defined in a parallel delivery.
/// This protocol provides a compile-time surface so `SidebarTreeViewModel`
/// can be tested without the actor being live.
public protocol OpenTabsPort: Sendable {
    /// Opens (or focuses) the given `DocumentTab`.
    func openTab(_ tab: DocumentTab) async
}

private struct UnimplementedOpenTabsPort: OpenTabsPort {
    func openTab(_ tab: DocumentTab) async {
        preconditionFailure("OpenTabsPort not injected — wire a real implementation at the composition root")
    }
}

private struct NoOpOpenTabsPort: OpenTabsPort {
    func openTab(_ tab: DocumentTab) async {}
}

extension DependencyValues {
    /// Access key for the `OpenTabsPort`.
    ///
    /// Wire the live `OpenTabsActor` at the composition root.
    /// Tests may supply `NoOpOpenTabsPort` or a spy double via `withDependencies`.
    var openTabs: any OpenTabsPort {
        get { self[OpenTabsDependencyKey.self] }
        set { self[OpenTabsDependencyKey.self] = newValue }
    }

    /// Access key for the `ClusterStripActor`.
    var clusterStrip: ClusterStripActor {
        get { self[ClusterStripDependencyKey.self] }
        set { self[ClusterStripDependencyKey.self] = newValue }
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

    /// Whether the active cluster's connection is established.
    public var isConnected: Bool = false

    /// The sidebar node currently selected (drives `List` highlight).
    public var selectedNode: SidebarNode?

    /// Set of group nodes that are currently expanded.
    public var expandedGroups: Set<SidebarNode> = []

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.clusterStrip) private var clusterStrip

    @ObservationIgnored
    @Dependency(\.openTabs) private var openTabs

    // MARK: Init

    public init() {}

    // MARK: - Lifecycle

    /// Subscribes to the `ClusterStripActor` state stream and keeps
    /// `activeClusterName` / `activeClusterId` up to date.
    ///
    /// Call once from a `.task {}` modifier on the owning view.
    public func start() async {
        log.info("SidebarTreeViewModel.start — subscribing to cluster strip")
        for await snapshot in clusterStrip.stateStream() {
            apply(snapshot: snapshot)
        }
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
        activeClusterId = snapshot.activeClusterId
        if let cid = snapshot.activeClusterId,
           let pin = snapshot.pins.first(where: { $0.clusterId == cid }) {
            activeClusterName = pin.displayName
            isConnected = true
        } else {
            activeClusterName = snapshot.pins.first?.displayName
            isConnected = false
        }
    }
}
