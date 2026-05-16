// Views/Chrome/TopRightChrome.swift — app_shell bounded context
// DDD role: Composite view — top-right chrome area (ADR-0051)
// ADR ref: ADR-0051 (top-right chrome), ADR-0034 (state-driven realtime UI)

import SwiftUI

// MARK: - TopRightChrome

/// Horizontal strip of three chrome controls placed at the top-right of the window.
///
/// Contains:
/// - `AssistantToggleButton` — opens/closes the assistant slide-out panel.
/// - `NotificationsButton` — opens `NotificationsPopover` with toast history.
/// - `UserMenuButton` — opens `UserMenuPopover` with account actions.
///
/// State is owned by `TopRightChromeViewModel`. The view starts the observation
/// task via `.task` so SwiftUI manages the lifecycle.
@MainActor
public struct TopRightChrome: View {

    @State private var viewModel = TopRightChromeViewModel()
    @State private var showUserMenu: Bool = false
    @Environment(\.appShellDependencies) private var deps

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            AssistantToggleButton(isOpen: viewModel.assistantPanelOpen) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.toggleAssistant()
                }
            }

            NotificationsButton(
                unreadCount: viewModel.unreadNotificationCount,
                isOpen: viewModel.notificationsOpen
            ) {
                viewModel.toggleNotifications()
            }
            .popover(isPresented: $viewModel.notificationsOpen, arrowEdge: .top) {
                NotificationsPopover(viewModel: viewModel)
            }

            UserMenuButton(initials: viewModel.userInitials) {
                viewModel.showUserMenu()
            }
            .popover(isPresented: $showUserMenu, arrowEdge: .top) {
                UserMenuPopover { showUserMenu = false }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .task { await viewModel.start(observing: ToastStackViewModel()) }
        .onReceive(NotificationCenter.default.publisher(for: .k8sManagerToggleAssistant)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.toggleAssistant()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .k8sManagerToggleNotifications)) { _ in
            viewModel.toggleNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: .k8sManagerShowUserMenu)) { _ in
            showUserMenu = true
        }
    }
}
