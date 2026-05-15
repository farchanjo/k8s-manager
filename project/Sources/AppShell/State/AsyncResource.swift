// State/AsyncResource.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states)

// MARK: - AsyncResource

/// Generic sum type representing the four lifecycle states of an async UI resource.
///
/// Conforms to `Sendable` so view models may store instances as `@Observable`
/// properties on a `@MainActor`-isolated type without triggering Swift 6
/// concurrency diagnostics.
///
/// Usage:
/// ```swift
/// var contexts: AsyncResource<[KubeconfigContext]> = .idle
/// ```
public enum AsyncResource<Value: Sendable>: Sendable {
    /// No load has been requested yet.
    case idle
    /// A load is in flight; the previous value (if any) is unavailable.
    case loading
    /// The load completed successfully.
    case success(Value)
    /// The load completed with an error.
    case failure(Error)

    // MARK: Convenience accessors

    /// The associated value when in the `.success` case; `nil` otherwise.
    public var value: Value? {
        if case .success(let v) = self { return v }
        return nil
    }

    /// The associated error when in the `.failure` case; `nil` otherwise.
    public var error: Error? {
        if case .failure(let e) = self { return e }
        return nil
    }

    /// `true` while a load is in flight.
    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// `true` when the resource is in the `.idle` state.
    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

// MARK: - Equatable conformance (Value: Equatable)

extension AsyncResource: Equatable where Value: Equatable {
    public static func == (lhs: AsyncResource<Value>, rhs: AsyncResource<Value>) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading):
            return true
        case (.success(let l), .success(let r)):
            return l == r
        case (.failure, .failure):
            return true
        default:
            return false
        }
    }
}
