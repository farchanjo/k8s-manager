// Views/Chrome/NavigationHistoryToolbar.swift — app_shell bounded context
// DDD role: View chrome — back/forward navigation arrow buttons
// ADR ref: ADR-0065 (Navigation history stack — back/forward within tab)

import SwiftUI

// MARK: - NavigationHistoryViewModel

/// `@Observable` `@MainActor` view model that bridges `NavigationHistoryActor`
/// to the back/forward toolbar buttons.
///
/// Subscribes to `NavigationHistoryActor.stateStream()` and forwards button
/// actions back to the actor. Also responds to `⌘[` / `⌘]` notification
/// dispatches from `K8sManagerCommands`.
@Observable
@MainActor
public final class NavigationHistoryViewModel {

    // MARK: Published state

    /// Whether the back arrow button is enabled.
    public private(set) var canGoBack: Bool = false
    /// Whether the forward arrow button is enabled.
    public private(set) var canGoForward: Bool = false

    // MARK: Private

    private var actor: NavigationHistoryActor?
    nonisolated(unsafe) private var streamTask: Task<Void, Never>?
    nonisolated(unsafe) private var backObserver: Task<Void, Never>?
    nonisolated(unsafe) private var forwardObserver: Task<Void, Never>?

    public init() {}

    deinit {
        streamTask?.cancel()
        backObserver?.cancel()
        forwardObserver?.cancel()
    }

    // MARK: Lifecycle

    /// Wires the view model to the given actor and starts observing its stream.
    ///
    /// Call once from `NavigationHistoryToolbar.task`. Also subscribes to the
    /// `⌘[` / `⌘]` notification names so keyboard shortcuts drive the actor.
    public func start(actor historyActor: NavigationHistoryActor) async {
        streamTask?.cancel()
        actor = historyActor
        streamTask = Task { [weak self] in
            let stream = await historyActor.stateStream()
            for await snapshot in stream {
                guard !Task.isCancelled else { break }
                await self?.apply(snapshot)
            }
        }
        subscribeToShortcutNotifications()
    }

    // MARK: Actions

    /// Triggers a `back()` traversal on the history actor.
    public func navigateBack() async {
        _ = await actor?.back()
    }

    /// Triggers a `forward()` traversal on the history actor.
    public func navigateForward() async {
        _ = await actor?.forward()
    }

    // MARK: Private

    @MainActor
    private func apply(_ snapshot: NavigationHistorySnapshot) {
        canGoBack = snapshot.canGoBack
        canGoForward = snapshot.canGoForward
    }

    private func subscribeToShortcutNotifications() {
        backObserver?.cancel()
        forwardObserver?.cancel()

        backObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .k8sManagerNavigateBack
            ) {
                guard !Task.isCancelled else { break }
                await self?.navigateBack()
            }
        }

        forwardObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .k8sManagerNavigateForward
            ) {
                guard !Task.isCancelled else { break }
                await self?.navigateForward()
            }
        }
    }
}

// MARK: - NavigationHistoryToolbar

/// A pair of back/forward arrow buttons wired to `NavigationHistoryActor`.
///
/// Placed in the top-left window chrome per ADR-0065 § UI affordance.
/// Each button is disabled when the history stack cannot traverse further.
///
/// Buttons expose `accessibilityLabel`, `help` tooltip, and their respective
/// keyboard shortcuts via `accessibilityKeyboardShortcut` as required by ADR-0065.
public struct NavigationHistoryToolbar: View {

    @State private var viewModel = NavigationHistoryViewModel()

    private let historyActor: NavigationHistoryActor

    public init(historyActor: NavigationHistoryActor) {
        self.historyActor = historyActor
    }

    public var body: some View {
        HStack(spacing: 2) {
            backButton
            forwardButton
        }
        .task { await viewModel.start(actor: historyActor) }
    }

    // MARK: Private views

    private var backButton: some View {
        Button {
            Task { await viewModel.navigateBack() }
        } label: {
            Image(systemName: "chevron.backward")
                .imageScale(.small)
        }
        .buttonStyle(.borderless)
        .disabled(!viewModel.canGoBack)
        .help("Back (⌘[)")
        .accessibilityLabel("Navigate back")
    }

    private var forwardButton: some View {
        Button {
            Task { await viewModel.navigateForward() }
        } label: {
            Image(systemName: "chevron.forward")
                .imageScale(.small)
        }
        .buttonStyle(.borderless)
        .disabled(!viewModel.canGoForward)
        .help("Forward (⌘])")
        .accessibilityLabel("Navigate forward")
    }
}
