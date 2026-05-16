// Views/TabBar/TabBarView.swift — app_shell bounded context
// DDD role: View chrome — horizontal tab bar + per-tab chip
// ADR ref: ADR-0050 (resource navigation taxonomy + tab system),
//          ADR-0034 (state-driven realtime UI — @Observable, no Combine)

import SharedKernel
import SwiftUI

// MARK: - TabBarViewModel

/// `@Observable` + `@MainActor` view model that bridges `OpenTabsActor` to SwiftUI.
///
/// Subscribes to `OpenTabsActor.stateStream()` inside a structured `Task` started
/// by `TabBarView.task`. Mutating operations are forwarded back to the actor.
@Observable
@MainActor
public final class TabBarViewModel {

    // MARK: Published state

    /// Current ordered list of tabs mirrored from `OpenTabsActor`.
    public private(set) var tabs: [DocumentTab] = []

    /// Id of the currently focused tab.
    public private(set) var activeTabId: TabId?

    // MARK: Private

    private var actor: OpenTabsActor?
    /// Stored `nonisolated(unsafe)` so `deinit` (which runs nonisolated) can cancel
    /// the task without a data-race warning under Swift 6 strict concurrency.
    nonisolated(unsafe) private var streamTask: Task<Void, Never>?

    public init() {}

    deinit {
        streamTask?.cancel()
    }

    // MARK: Lifecycle

    /// Wires the view model to the given actor and starts observing its stream.
    ///
    /// Call once from `TabBarView.task`. Idempotent — subsequent calls replace
    /// the previous subscription cleanly.
    public func start(actor openTabsActor: OpenTabsActor) async {
        streamTask?.cancel()
        actor = openTabsActor
        streamTask = Task { [weak self] in
            let stream = await openTabsActor.stateStream()
            for await snapshot in stream {
                guard !Task.isCancelled else { break }
                self?.apply(snapshot)
            }
        }
    }

    // MARK: Actions

    /// Requests the actor to focus the tab identified by `id`.
    public func focus(_ id: TabId) async {
        await actor?.focusTab(id)
    }

    /// Requests the actor to close the tab identified by `id`.
    public func close(_ id: TabId) async {
        await actor?.closeTab(id)
    }

    /// Requests the actor to close all tabs except the one identified by `keepId`.
    ///
    /// Tabs whose `isCloseable == false` (e.g. the workspace Welcome tab) are
    /// preserved regardless of the keep selection. Closeability is enforced
    /// per ADR-0054 for workspace-scoped surfaces.
    public func closeOthers(keeping keepId: TabId) async {
        guard let actor else { return }
        let toClose = tabs
            .filter { $0.id != keepId && $0.isCloseable }
            .map(\.id)
        for id in toClose { await actor.closeTab(id) }
    }

    /// Requests the actor to close all tabs to the right of `anchorId`.
    ///
    /// Non-closeable tabs (workspace Welcome, etc.) are skipped per ADR-0054.
    public func closeToRight(of anchorId: TabId) async {
        guard let actor,
              let anchorIdx = tabs.firstIndex(where: { $0.id == anchorId }) else { return }
        let toClose = tabs[(anchorIdx + 1)...]
            .filter(\.isCloseable)
            .map(\.id)
        for id in toClose { await actor.closeTab(id) }
    }

    // MARK: Private

    private func apply(_ snapshot: OpenTabsSnapshot) {
        tabs = snapshot.tabs
        activeTabId = snapshot.activeTabId
    }
}

// MARK: - TabBarView

/// Horizontally scrollable tab bar rendered above the main content canvas.
///
/// Wires to `OpenTabsActor` via `TabBarViewModel`. Each tab is represented by a
/// `TabChip` that supports tap-to-focus, close button, and a context menu with
/// close-others and close-to-right actions.
///
/// Per ADR-0050 the bar is 32 pt tall, uses `.bar` material, and shows no
/// scrollbar indicator.
public struct TabBarView: View {

    @State private var viewModel = TabBarViewModel()

    /// The actor to subscribe to. Injected from the parent that owns the actor.
    private let openTabsActor: OpenTabsActor

    /// Optional callback invoked whenever a cluster tab is focused by the user.
    ///
    /// Used by parents that coordinate with a sibling workspace-tab surface
    /// (ADR-0054) so the workspace Welcome chip can clear its "active" state
    /// the moment a cluster tab takes focus.
    private let onTabFocused: ((TabId) -> Void)?

    /// Optional override for the visually active tab id.
    ///
    /// When non-nil, takes precedence over `OpenTabsActor`'s own `activeTabId`
    /// for rendering. Parents pass `nil` here when they want the cluster tabs
    /// to act as the sole active source; they pass a non-cluster id (e.g. the
    /// workspace Welcome tab id) to clear every cluster chip's active state.
    private let externalActiveOverride: TabId?

    public init(
        openTabsActor: OpenTabsActor,
        externalActiveOverride: TabId? = nil,
        onTabFocused: ((TabId) -> Void)? = nil
    ) {
        self.openTabsActor = openTabsActor
        self.externalActiveOverride = externalActiveOverride
        self.onTabFocused = onTabFocused
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(viewModel.tabs) { tab in
                    TabChip(tab: tab, isActive: isChipActive(tab)) {
                        Task { await viewModel.focus(tab.id) }
                        onTabFocused?(tab.id)
                    } onClose: {
                        Task { await viewModel.close(tab.id) }
                    }
                    .contextMenu {
                        tabContextMenu(for: tab)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.18), value: viewModel.tabs.map(\.id))
        }
        .frame(height: 32)
        .background(.bar)
        .task { await viewModel.start(actor: openTabsActor) }
    }

    /// `true` when the cluster chip should render its active style.
    ///
    /// Cluster chips defer to the external override when present (so a
    /// workspace Welcome focus visually deactivates every cluster chip).
    private func isChipActive(_ tab: DocumentTab) -> Bool {
        if let override = externalActiveOverride {
            return tab.id == override
        }
        return tab.id == viewModel.activeTabId
    }

    // MARK: Context menu

    @ViewBuilder
    private func tabContextMenu(for tab: DocumentTab) -> some View {
        if tab.isCloseable {
            Button("Close Tab") {
                Task { await viewModel.close(tab.id) }
            }
        }
        Button("Close Other Tabs") {
            Task { await viewModel.closeOthers(keeping: tab.id) }
        }
        Button("Close Tabs to the Right") {
            Task { await viewModel.closeToRight(of: tab.id) }
        }
    }
}

// MARK: - TabChip

/// A single tab chip rendering icon + title + close button.
///
/// Active chips use a lighter fill; inactive chips are transparent with a hover
/// highlight. The close button appears on hover and always when the chip is active.
struct TabChip: View {

    let tab: DocumentTab
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)

            closeButton
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 80, maxWidth: 200, maxHeight: .infinity)
        .background(chipBackground)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(tab.title), tab")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: Sub-views

    @ViewBuilder
    private var closeButton: some View {
        if tab.isCloseable, isActive || isHovering {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(tab.title)")
        } else {
            // Reserve space so chip width stays stable on hover; for permanently
            // non-closeable tabs (welcome) this keeps the chip layout uniform.
            Color.clear
                .frame(width: 14, height: 14)
        }
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
