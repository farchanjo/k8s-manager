// Views/Sidebar/SidebarCanvasView.swift — app_shell bounded context
// DDD role: View — canvas area (tab bar + active tab content)
// ADR ref: ADR-0050 (multi-document tab system), ADR-0051 (Lens-style canvas layout)

import SwiftUI
import SharedKernel

// MARK: - SidebarCanvasView

/// Canvas area that combines the horizontal tab bar with the active tab content view.
///
/// Owns a `TabBarViewModel` so the active tab can be derived synchronously
/// in `ActiveTabContentView` without crossing the actor boundary at render time.
///
/// Usage:
/// ```swift
/// SidebarCanvasView(openTabsActor: deps.openTabsActor)
/// ```
public struct SidebarCanvasView: View {

    // MARK: Init parameters

    private let openTabsActor: OpenTabsActor?

    // MARK: View model (tracks which tab is active)

    @State private var tabBarViewModel = TabBarViewModel()

    public init(openTabsActor: OpenTabsActor?) {
        self.openTabsActor = openTabsActor
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
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
