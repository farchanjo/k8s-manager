// State/AsyncLoader.swift — app_shell bounded context
// DDD role: Service — 200 ms throttle helper for AsyncResource transitions
// ADR ref: ADR-0031 §"200 ms transition throttle"

import Foundation

// MARK: - AsyncLoader

/// Helper that wraps an `async throws -> T` operation with the canonical
/// ADR-0031 lifecycle:
///
/// 1. Schedule a 200 ms sleep.
/// 2. Race the sleep against the underlying operation.
/// 3. If the sleep completes first the caller transitions to `.loading`;
///    otherwise the operation already returned and `.success` is emitted
///    directly — no visible flash for sub-200 ms operations.
///
/// Used inside `@Observable @MainActor` view models:
///
/// ```swift
/// loadState = .loading
/// await AsyncLoader.run(
///     setLoading: { self.loadState = .loading },
///     operation: { try await self.listPort.list(...) },
///     onSuccess: { self.rows = $0; self.loadState = .success($0.count) },
///     onFailure: { self.loadState = .failure($0) }
/// )
/// ```
///
/// The helper is `Sendable` (struct with no stored state) and safe to call
/// from any actor.
public enum AsyncLoader {

    /// Throttle window before the loading callback fires.
    public static let throttleInterval: Duration = .milliseconds(200)

    /// Runs `operation` with a 200 ms `.idle → .loading` throttle.
    ///
    /// - Parameters:
    ///   - setLoading: Invoked after the throttle elapses if the operation
    ///     is still running. Caller flips its `AsyncResource` to `.loading`.
    ///   - operation: The actual work to perform. May throw.
    ///   - onSuccess: Invoked with the resolved value when `operation`
    ///     completes successfully.
    ///   - onFailure: Invoked with the thrown error when `operation` fails.
    ///
    /// Cancellation: caller's enclosing `Task` cancellation propagates into
    /// `operation` via Swift structured concurrency.
    @MainActor
    public static func run<T: Sendable>(
        setLoading: @MainActor () -> Void,
        operation: @Sendable @escaping () async throws -> T,
        onSuccess: @MainActor (T) -> Void,
        onFailure: @MainActor (Error) -> Void
    ) async {
        let workTask = Task<T, Error> { try await operation() }
        let sleepTask = Task<Bool, Never> {
            (try? await Task.sleep(for: throttleInterval)) != nil
        }
        // Wait whichever finishes first.
        let workIsDone = await raceWorkVsSleep(workTask: workTask, sleepTask: sleepTask)
        if !workIsDone {
            setLoading()
        }
        do {
            let value = try await workTask.value
            onSuccess(value)
        } catch {
            onFailure(error)
        }
    }

    /// Returns `true` when the work task completed before the sleep window
    /// elapsed; `false` when the sleep window won.
    private static func raceWorkVsSleep<T: Sendable>(
        workTask: Task<T, Error>,
        sleepTask: Task<Bool, Never>
    ) async -> Bool {
        await withTaskGroup(of: WhoFinishedFirst.self, returning: Bool.self) { group in
            group.addTask { _ = try? await workTask.value; return .work }
            group.addTask { _ = await sleepTask.value; return .sleep }
            let winner = await group.next() ?? .sleep
            group.cancelAll()
            return winner == .work
        }
    }

    private enum WhoFinishedFirst { case work, sleep }
}
