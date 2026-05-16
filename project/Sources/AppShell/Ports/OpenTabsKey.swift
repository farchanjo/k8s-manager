// Ports/OpenTabsKey.swift — app_shell bounded context
// DDD role: SwiftUI EnvironmentKey for OpenTabsActor
// ADR ref: ADR-0050 (resource navigation taxonomy + tab system)

import SwiftUI

// MARK: - EnvironmentKey

private struct OpenTabsActorKey: EnvironmentKey {
    /// Default is `nil` — callers that need the actor must receive it from a
    /// parent that injected one. Views that render conditionally on tab state
    /// should guard on a non-nil value.
    static let defaultValue: OpenTabsActor? = nil
}

// MARK: - EnvironmentValues extension

public extension EnvironmentValues {
    /// The `OpenTabsActor` for the nearest enclosing cluster context, or `nil`
    /// when no tab session is active.
    ///
    /// Access via `@Environment(\.openTabsActor) private var openTabsActor` in
    /// any view or `@MainActor` type that is part of the SwiftUI view tree.
    var openTabsActor: OpenTabsActor? {
        get { self[OpenTabsActorKey.self] }
        set { self[OpenTabsActorKey.self] = newValue }
    }
}

// MARK: - View modifier convenience

public extension View {
    /// Injects the given `OpenTabsActor` into the SwiftUI environment.
    ///
    /// Typically called by the composition root after constructing an actor for
    /// the active cluster:
    /// ```swift
    /// ContentView()
    ///     .openTabsActor(actor)
    /// ```
    func openTabsActor(_ actor: OpenTabsActor) -> some View {
        environment(\.openTabsActor, actor)
    }
}
