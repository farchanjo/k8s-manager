// Views/Sidebar/SidebarCanvasView.swift — app_shell bounded context
// DDD role: View — canvas area (header + tab bar + active tab content)
// ADR ref: ADR-0050 (multi-document tab system), ADR-0051 (Lens-style canvas layout)
// ADR ref: ADR-0054 (persistent workspace Welcome tab)

import SwiftUI
import SharedKernel

// MARK: - SidebarCanvasView

/// Canvas area combining a header strip (namespace picker), the horizontal
/// tab bar, and the active tab content view.
///
/// Per ADR-0054 the tab bar renders a persistent workspace Welcome chip at
/// position 0 in addition to the per-cluster tabs sourced from
/// ``OpenTabsActor``. The canvas treats the Welcome tab as the sole active
/// surface whenever it is selected, regardless of the cluster's own active
/// tab id.
public struct SidebarCanvasView: View {

    // MARK: Init parameters

    private let openTabsActor: OpenTabsActor?
    private let activeClusterId: ClusterId?

    // MARK: View models

    /// View model bridging the per-cluster tab actor to SwiftUI.
    @State private var tabBarViewModel = TabBarViewModel()

    // MARK: Workspace tab state (ADR-0054)

    /// Whether the workspace Welcome tab is currently the active surface.
    ///
    /// Toggled by user interaction with the leading Welcome chip and by the
    /// `⌘⇧W` shortcut / command palette entry. Mutually exclusive with
    /// `tabBarViewModel.activeTabId` — when this is `true`, the cluster tab
    /// bar renders every chip inactive.
    @State private var workspaceActive: Bool = true

    /// Snapshot of workspace-scoped tabs (currently always `[.welcome]`).
    /// Stored so the view re-renders when the actor's snapshot changes.
    @State private var workspaceTabs: [DocumentTab] = [.welcome]

    @Environment(\.appShellDependencies) private var deps

    public init(openTabsActor: OpenTabsActor?, activeClusterId: ClusterId? = nil) {
        self.openTabsActor = openTabsActor
        self.activeClusterId = activeClusterId
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            tabBarRow
            Divider()
            activeContent
        }
        .task {
            guard let actor = openTabsActor else { return }
            await tabBarViewModel.start(actor: actor)
        }
        .task(id: deps.workspaceTabsActor.map(ObjectIdentifier.init)) {
            await observeWorkspaceTabs()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .k8sManagerFocusWelcomeTab)
        ) { _ in
            focusWelcomeTab()
        }
    }

    // MARK: Private

    /// Header strip is always rendered so the SwiftUI view tree above the
    /// tab bar stays structurally stable. The namespace picker appears only
    /// when there is an active cluster; otherwise the strip occupies the
    /// same space with an invisible placeholder, preventing the tab bar from
    /// jumping vertically each time `ClusterStripActor` re-emits a snapshot.
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

    /// Combined tab bar row — workspace Welcome chip (ADR-0054) followed by
    /// the per-cluster tab list. Both segments share a single visual bar.
    private var tabBarRow: some View {
        HStack(spacing: 0) {
            WelcomeTabChip(
                isActive: workspaceActive,
                onTap: focusWelcomeTab
            )

            if let actor = openTabsActor {
                TabBarView(
                    openTabsActor: actor,
                    externalActiveOverride: workspaceActive
                        ? DocumentTab.welcome.id
                        : nil,
                    onTabFocused: { _ in workspaceActive = false }
                )
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            } else {
                Spacer()
                    .frame(height: 32)
            }
        }
        .frame(height: 32)
        .background(.bar)
    }

    private var activeContent: some View {
        ActiveTabContentView(activeTab: activeTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Resolves the active `DocumentTab`. The workspace Welcome surface takes
    /// precedence whenever `workspaceActive` is set.
    private var activeTab: DocumentTab? {
        if workspaceActive { return .welcome }
        guard let activeId = tabBarViewModel.activeTabId else { return nil }
        return tabBarViewModel.tabs.first { $0.id == activeId }
    }

    /// Activates the workspace Welcome tab and bridges to the underlying actor.
    private func focusWelcomeTab() {
        workspaceActive = true
        if let actor = deps.workspaceTabsActor {
            Task { await actor.focusWelcome() }
        }
    }

    /// Subscribes to the workspace tabs actor so the local snapshot stays
    /// current. Currently the only workspace tab is Welcome so the list is
    /// constant, but the subscription keeps the structure ready for future
    /// workspace-scoped tabs (What's New, Diagnostics, etc.).
    private func observeWorkspaceTabs() async {
        guard let actor = deps.workspaceTabsActor else { return }
        for await snapshot in await actor.stateStream() {
            workspaceTabs = snapshot.tabs
        }
    }
}

// MARK: - WelcomeTabChip

/// Leading chip rendered to the left of the cluster tab bar.
///
/// Mirrors the visual language of `TabChip` (in `TabBarView`) so the bar
/// reads as a single uniform surface. The chip is permanently non-closeable
/// per ADR-0054 § "Never auto-closed".
private struct WelcomeTabChip: View {

    let isActive: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: DocumentTab.welcome.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(DocumentTab.welcome.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)

            // Reserve the same trailing width as the close button slot in
            // other chips so the layout reads as a uniform bar.
            Color.clear.frame(width: 14, height: 14)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 80, maxWidth: 200, maxHeight: .infinity)
        .background(chipBackground)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { isHovering = $0 }
        .accessibilityLabel("Welcome tab")
        .accessibilityIdentifier("WelcomeTabChip")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isActive {
            RoundedRectangle(cornerRadius: 4)
                .fill(.background.opacity(0.85))
        } else if isHovering {
            RoundedRectangle(cornerRadius: 4)
                .fill(.primary.opacity(0.06))
        } else {
            Color.clear
        }
    }
}
