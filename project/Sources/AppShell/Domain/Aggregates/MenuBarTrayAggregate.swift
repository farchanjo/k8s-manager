// Domain/Aggregates/MenuBarTrayAggregate.swift — app_shell bounded context
// DDD role: AggregateRoot orchestration (actor)
// ADR ref: ADR-0022, ADR-0034

import Foundation

/// Actor orchestrating all mutable state for the menu bar tray.
///
/// Provides thread-safe access to `MenuBarTray` preferences and coordinates
/// `TrayRefreshEvent` transitions.
public actor MenuBarTrayAggregate {

    // MARK: State

    private var state: MenuBarTray
    private var continuations: [UUID: AsyncStream<MenuBarTray>.Continuation] = [:]

    // MARK: Init

    public init(initial: MenuBarTray) {
        self.state = initial
    }

    // MARK: Read

    public var current: MenuBarTray { state }

    // MARK: Transitions

    /// Updates `iconState` after a refresh cycle completes.
    public func applyRefreshEvent(_ event: TrayRefreshEvent) {
        switch event {
        case .succeeded(_, _):
            state.lastRefreshedAtRFC3339 = ISO8601DateFormatter().string(from: Date())
            state.iconState = .online
        case .failed(_, _):
            state.iconState = .degraded
        case .paused(_), .resumed, .requested(_):
            break
        }
        broadcast()
    }

    /// Updates popover lifecycle state.
    public func setPopoverState(_ popoverState: MenuBarTray.PopoverState) {
        state.popoverState = popoverState
        broadcast()
    }

    /// Updates operator-configured preferences (persisted by caller).
    public func updatePreferences(
        displayMode: MenuBarTray.DisplayMode? = nil,
        refreshInterval: MenuBarTray.RefreshInterval? = nil,
        manualRefreshOnly: Bool? = nil,
        backgroundRefreshEnabled: Bool? = nil,
        popoverPinned: Bool? = nil
    ) {
        if let v = displayMode { state.displayMode = v }
        if let v = refreshInterval { state.refreshIntervalSeconds = v }
        if let v = manualRefreshOnly { state.manualRefreshOnly = v }
        if let v = backgroundRefreshEnabled { state.backgroundRefreshEnabled = v }
        if let v = popoverPinned { state.popoverPinned = v }
        broadcast()
    }

    /// Returns an `AsyncStream` of state snapshots for observers.
    public func stateStream() -> AsyncStream<MenuBarTray> {
        let key = UUID()
        return AsyncStream { continuation in
            Task { await self.addContinuation(continuation, key: key) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(key: key) }
            }
        }
    }

    // MARK: Private

    private func addContinuation(_ continuation: AsyncStream<MenuBarTray>.Continuation, key: UUID) {
        continuation.yield(state)
        continuations[key] = continuation
    }

    private func removeContinuation(key: UUID) {
        continuations.removeValue(forKey: key)
    }

    private func broadcast() {
        for cont in continuations.values { cont.yield(state) }
    }
}
