// Domain/ObservableState.swift — app_shell bounded context
// DDD role: ValueObject (specification/marker)
// CUE source: docs/arch/contexts/app_shell/schemas/observable_state.cue
// ADR ref: ADR-0034

// MARK: - UpdateSource

/// Describes what produces changes to an `@Observable` property.
public enum UpdateSource: String, Sendable, Codable {
    case actorStreamedEvent = "actor_streamed_event"
    case asyncResourceLoaded = "async_resource_loaded"
    case userAction = "user_action"
}

// MARK: - ConsumerScope

/// Describes which part of the view hierarchy reads an `@Observable` property.
public enum ConsumerScope: String, Sendable, Codable {
    case mainActor = "MainActor"
    case detailView = "DetailView"
    case globalEnvironment = "GlobalEnvironment"
}

// MARK: - ObservableStateContract

/// Specification record documenting the binding contract between domain actor state
/// and `@Observable` SwiftUI view models (ADR-0034).
///
/// Used by architecture review tooling — not loaded at runtime.
public struct ObservableStateContract: Sendable, Codable {
    /// Kebab-case slug uniquely identifying the state property within its view model.
    public let stateId: String
    /// What produces changes to this state.
    public let updateSource: UpdateSource
    /// Which part of the view hierarchy reads this state.
    public let consumerScope: ConsumerScope
    /// `true` for `actor_streamed_event` and `async_resource_loaded` — state transitions
    /// to `.idle` / neutral when the parent Task is cancelled.
    public let reactToCancellation: Bool
    /// `true` for `@ObservationIgnored` implementation details (e.g. `watchTask`).
    public let observationIgnored: Bool

    public init(
        stateId: String,
        updateSource: UpdateSource,
        consumerScope: ConsumerScope,
        reactToCancellation: Bool = true,
        observationIgnored: Bool = false
    ) {
        self.stateId = stateId
        self.updateSource = updateSource
        self.consumerScope = consumerScope
        self.reactToCancellation = reactToCancellation
        self.observationIgnored = observationIgnored
    }
}

// MARK: - AppShellObservableModel (marker protocol)

/// Marker protocol adopted by all `@Observable` view model classes in `app_shell`.
///
/// Architecture invariants (ADR-0034):
/// - Conforming types **must** be `@MainActor`-isolated.
/// - No domain service or port may import SwiftUI.
/// - Shared state propagated via `@Environment`, not constructor chains.
/// - No Combine publisher or `AnyCancellable` in new conforming files.
public protocol AppShellObservableModel: AnyObject, Sendable {}
