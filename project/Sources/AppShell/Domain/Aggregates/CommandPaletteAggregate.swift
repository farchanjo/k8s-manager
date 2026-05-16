// Domain/Aggregates/CommandPaletteAggregate.swift — app_shell bounded context
// DDD role: AggregateRoot orchestration (actor)
// ADR ref: ADR-0023, ADR-0034

import Foundation

/// Actor orchestrating the command palette aggregate.
///
/// Thread-safe owner of `CommandPalette` state. The SwiftUI overlay observes
/// state changes via `stateStream()`. The `CommandResolverService` and
/// `ShortcutDispatchService` drive mutations through this actor.
public actor CommandPaletteAggregate {

    // MARK: State

    private var state: CommandPalette
    private var continuations: [UUID: AsyncStream<CommandPalette>.Continuation] = [:]

    // MARK: Init

    public init(initial: CommandPalette) {
        self.state = initial
    }

    // MARK: Read

    public var current: CommandPalette { state }

    // MARK: Transitions

    /// Opens the palette overlay and resets the query and cursor.
    public func open() {
        state.isOpen = true
        state.query = ""
        state.selectedIndex = 0
        broadcast()
    }

    /// Closes the palette and returns keyboard focus to the trigger element.
    public func close() {
        state.isOpen = false
        broadcast()
    }

    /// Updates the incremental search string and resets the cursor.
    public func updateQuery(_ query: String) {
        state.query = query
        state.selectedIndex = 0
        broadcast()
    }

    /// Moves the cursor by `delta` (wraps at both ends for `resultCount` items).
    public func moveCursor(by delta: Int, resultCount: Int) {
        guard resultCount > 0 else { return }
        state.selectedIndex = ((state.selectedIndex + delta) % resultCount + resultCount) % resultCount
        broadcast()
    }

    /// Records a command invocation in the recent-invocations ring (max 50).
    public func recordInvocation(commandId: String, durationMillis: Int) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let invocation = CommandInvocation(
            commandId: commandId,
            invokedAt: timestamp,
            durationMillis: durationMillis
        )
        state.recordInvocation(invocation)
        broadcast()
    }

    /// Replaces the persisted recent invocations (called on cold launch hydration).
    public func hydrateRecents(_ invocations: [CommandInvocation]) {
        state.recentInvocations = Array(invocations.prefix(50))
        broadcast()
    }

    /// Returns an `AsyncStream` of state snapshots for observers.
    public func stateStream() -> AsyncStream<CommandPalette> {
        let key = UUID()
        return AsyncStream { continuation in
            Task { await self.addContinuation(continuation, key: key) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(key: key) }
            }
        }
    }

    // MARK: Private

    private func addContinuation(_ continuation: AsyncStream<CommandPalette>.Continuation, key: UUID) {
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
