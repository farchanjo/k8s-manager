// Views/Chrome/DockedTerminalPane.swift — app_shell bounded context
// DDD role: View — bottom-docked terminal pane chrome
// ADR ref: ADR-0057 (bottom-docked terminal pane with node-debug shell integration)

import SwiftUI
import SharedKernel

// MARK: - DockedTerminalPane

/// Bottom-docked pane chrome: resize handle, tab strip, and active PTY viewport.
///
/// Reuses ``TerminalView`` for the PTY surface. `DockedTerminalPaneActor` is the
/// single source of truth; this view is a pure projection.
///
/// The pane is hidden (zero height) when `snapshot.isOpen == false`. It slides
/// in with a spring animation on first tab open, per ADR-0057 §Bottom pane chrome.
public struct DockedTerminalPane: View {

    // MARK: Input

    /// The actor owning pane state. Passed in by `SidebarCanvasView`.
    let actor: DockedTerminalPaneActor

    // MARK: Observed state

    @State private var snapshot: DockedTerminalPaneSnapshot = .init(
        state: DockedTerminalPaneState()
    )

    // MARK: Geometry state

    /// Height stored in the actor; local copy for smooth drag feedback.
    @State private var localHeight: Double = 240

    /// Height captured at the start of a drag gesture.
    @State private var dragBaseHeight: Double = 240

    /// Height captured before entering fullscreen (for restore on exit).
    @State private var preFullscreenHeight: Double = 240

    // MARK: Body

    public var body: some View {
        Group {
            if snapshot.isOpen {
                paneContent
                    .frame(height: snapshot.state.fullscreen ? nil : localHeight)
                    .frame(maxHeight: snapshot.state.fullscreen ? .infinity : nil)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(duration: 0.18, bounce: 0.1), value: snapshot.isOpen)
        .task {
            for await s in await actor.stateStream() {
                snapshot = s
                if !s.state.fullscreen {
                    localHeight = s.state.paneHeight
                }
            }
        }
    }

    // MARK: - Pane content

    private var paneContent: some View {
        VStack(spacing: 0) {
            resizeHandle
            Divider()
            tabBarRow
            Divider()
            ptyViewport
        }
        .background(.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    // MARK: - Resize handle

    private var resizeHandle: some View {
        Color.primary.opacity(0.12)
            .frame(height: 4)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onTapGesture(count: 2) { resetHeight() }
            .accessibilityLabel("Drag to resize terminal pane")
            .accessibilityIdentifier("DockedTerminalPane.ResizeHandle")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let delta = -value.translation.height
                localHeight = max(120, dragBaseHeight + delta)
            }
            .onEnded { _ in
                dragBaseHeight = localHeight
                Task { await actor.setPaneHeight(localHeight) }
            }
    }

    private func resetHeight() {
        localHeight = 240
        dragBaseHeight = 240
        Task { await actor.setPaneHeight(240) }
    }

    // MARK: - Tab bar row

    private var tabBarRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(snapshot.tabs) { tab in
                        DockedTerminalTabChip(
                            tab: tab,
                            isActive: snapshot.activeTabId == tab.id,
                            onSelect: { Task { await actor.focusTab(tab.id) } },
                            onClose: { Task { await actor.closeTab(tab.id) } }
                        )
                    }
                }
            }
            Spacer(minLength: 0)
            fullscreenToggleButton
        }
        .frame(height: 28)
        .background(.bar)
    }

    private var fullscreenToggleButton: some View {
        Button {
            Task { await toggleFullscreen() }
        } label: {
            Image(
                systemName: snapshot.state.fullscreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right"
            )
            .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityLabel(
            snapshot.state.fullscreen ? "Collapse terminal pane" : "Expand terminal pane"
        )
        .accessibilityIdentifier("DockedTerminalPane.FullscreenToggle")
    }

    private func toggleFullscreen() async {
        if !snapshot.state.fullscreen {
            preFullscreenHeight = localHeight
        } else {
            localHeight = preFullscreenHeight
        }
        await actor.toggleFullscreen()
    }

    // MARK: - PTY viewport

    private var ptyViewport: some View {
        Group {
            if let activeId = snapshot.activeTabId,
               let tab = snapshot.tabs.first(where: { $0.id == activeId }) {
                TerminalTabContent(tab: tab)
            } else {
                emptyViewport
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyViewport: some View {
        Color.black
            .overlay(
                Text("No active terminal session")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, design: .monospaced))
            )
    }
}

// MARK: - DockedTerminalTabChip

/// One tab button in the docked pane tab strip.
private struct DockedTerminalTabChip: View {

    let tab: DockedTerminalTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            connectionDot
                .padding(.leading, 6)

            Text(tab.label)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(maxWidth: 180)

            closeButton
                .opacity(isHovering || isActive ? 1 : 0)
                .padding(.trailing, 4)
        }
        .frame(height: 28)
        .background(chipBackground)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var connectionDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }

    private var dotColor: Color {
        switch tab.connectionState {
        case .open:              return .green
        case .opening, .closing: return .yellow
        case .closed, .error:    return .red
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 14, height: 14)
        .contentShape(Rectangle())
        .accessibilityLabel("Close \(tab.label)")
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isActive {
            RoundedRectangle(cornerRadius: 0)
                .fill(.background.opacity(0.85))
        } else if isHovering {
            RoundedRectangle(cornerRadius: 0)
                .fill(.primary.opacity(0.06))
        } else {
            Color.clear
        }
    }
}

// MARK: - TerminalTabContent

/// PTY viewport for a single docked terminal tab.
///
/// Renders a connection state banner while the session is not yet open;
/// falls through to ``TerminalView`` once the session is live.
private struct TerminalTabContent: View {

    let tab: DockedTerminalTab

    var body: some View {
        switch tab.connectionState {
        case .open:
            liveTerminal
        case .opening:
            banner(message: "Connecting ...", showSpinner: true, action: nil)
        case .closing:
            banner(message: "Closing ...", showSpinner: true, action: nil)
        case .closed:
            banner(message: "Session closed", showSpinner: false, action: ("Reopen", {}))
        case .error:
            banner(message: "Connection failed", showSpinner: false, action: ("Retry", {}))
        }
    }

    private var liveTerminal: some View {
        TerminalView(
            output: "",
            onInput: { _ in },
            onResize: { _, _ in }
        )
    }

    private func banner(
        message: String,
        showSpinner: Bool,
        action: (label: String, handler: () -> Void)?
    ) -> some View {
        ZStack {
            Color.black
            VStack(spacing: 8) {
                if showSpinner { ProgressView().controlSize(.small) }
                Text(message)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let action {
                    Button(action.label, action: action.handler)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .accessibilityIdentifier("DockedTerminalPane.Banner.\(tab.id)")
    }
}
