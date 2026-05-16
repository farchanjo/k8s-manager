// Views/Sidebar/SidebarCanvasView.swift — app_shell bounded context
// DDD role: View — canvas area (header + tab bar + active tab content)
// ADR ref: ADR-0050 (multi-document tab system), ADR-0051 (Lens-style canvas layout)

import SwiftUI
import SharedKernel

// MARK: - SidebarCanvasView

/// Canvas area combining a header strip (namespace picker), the horizontal
/// tab bar, and the active tab content view.
///
/// The header is rendered only when there is an active cluster, so the
/// picker never appears in a "no cluster selected" state.
public struct SidebarCanvasView: View {

    // MARK: Init parameters

    private let openTabsActor: OpenTabsActor?
    private let activeClusterId: ClusterId?

    // MARK: View model (tracks which tab is active)

    @State private var tabBarViewModel = TabBarViewModel()

    public init(openTabsActor: OpenTabsActor?, activeClusterId: ClusterId? = nil) {
        self.openTabsActor = openTabsActor
        self.activeClusterId = activeClusterId
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            tabBar
            Divider()
            activeContent
        }
        .task {
            guard let actor = openTabsActor else { return }
            await tabBarViewModel.start(actor: actor)
        }
    }

    // MARK: Private

    /// Header strip is always rendered so the SwiftUI view tree above the
    /// tab bar stays structurally stable. The namespace picker appears only
    /// when there is an active cluster; otherwise the strip occupies the
    /// same space with an invisible placeholder, preventing the tab bar from
    /// jumping vertically each time `ClusterStripActor` re-emits a snapshot.
    ///
    /// The strip uses a fixed `minHeight` so the canvas geometry never shifts
    /// vertically between "no cluster" and "cluster active" states.
    private var headerBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                if let clusterId = activeClusterId {
                    GlobalNamespacePicker(clusterId: clusterId)
                } else {
                    Color.clear.frame(width: 160, height: 28)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 40)
            .background(.regularMaterial)
            Divider()
        }
    }

    @ViewBuilder
    private var tabBar: some View {
        if let actor = openTabsActor {
            TabBarView(openTabsActor: actor)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
        }
    }

    private var activeContent: some View {
        ActiveTabContentView(activeTab: activeTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Resolves the active `DocumentTab` from the `TabBarViewModel` synchronously.
    private var activeTab: DocumentTab? {
        guard let activeId = tabBarViewModel.activeTabId else { return nil }
        return tabBarViewModel.tabs.first { $0.id == activeId }
    }
}
