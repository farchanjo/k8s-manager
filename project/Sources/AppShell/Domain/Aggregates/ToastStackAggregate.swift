// Domain/Aggregates/ToastStackAggregate.swift — app_shell bounded context
// DDD role: AggregateRoot orchestration (actor)
// ADR ref: ADR-0032, ADR-0034

import Foundation

/// Actor orchestrating the global domain toast stack.
///
/// `ToastDomainEmitter` enqueues toasts; `ToastDismissScheduler` calls `dismiss(id:)`.
/// SwiftUI reads state via `stateStream()` inside a `@MainActor` Task.
public actor ToastStackAggregate {

    // MARK: State

    private var stack: DomainToastStack
    private var continuations: [UUID: AsyncStream<DomainToastStack>.Continuation] = [:]

    // MARK: Init

    public init(initial: DomainToastStack) {
        self.stack = initial
    }

    // MARK: Read

    public var current: DomainToastStack { stack }

    // MARK: Mutations

    /// Enqueues a new toast, evicting the oldest non-pinned entry if at capacity.
    public func enqueue(_ toast: Toast) {
        stack.enqueue(toast)
        broadcast()
    }

    /// Dismisses a toast by id. Promotes the next queued toast if one exists.
    public func dismiss(id: String) {
        stack.dismiss(id: id)
        broadcast()
    }

    /// Pins or unpins a toast so the auto-dismiss timer is suppressed.
    public func setPin(_ pinned: Bool, id: String) {
        guard let idx = stack.activeToasts.firstIndex(where: { $0.id == id }) else { return }
        stack.activeToasts[idx].pinned = pinned
        broadcast()
    }

    /// Updates stack position preference (persisted by caller).
    public func setPosition(_ position: DomainToastStack.Position) {
        stack.position = position
        broadcast()
    }

    /// Returns an `AsyncStream` of stack snapshots for `@MainActor` observers.
    public func stateStream() -> AsyncStream<DomainToastStack> {
        let key = UUID()
        return AsyncStream { continuation in
            Task {
                await self.addContinuation(continuation, key: key)
            }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(key: key) }
            }
        }
    }

    // MARK: Private

    private func addContinuation(_ continuation: AsyncStream<DomainToastStack>.Continuation, key: UUID) {
        continuation.yield(stack)
        continuations[key] = continuation
    }

    private func removeContinuation(key: UUID) {
        continuations.removeValue(forKey: key)
    }

    private func broadcast() {
        for cont in continuations.values { cont.yield(stack) }
    }
}
