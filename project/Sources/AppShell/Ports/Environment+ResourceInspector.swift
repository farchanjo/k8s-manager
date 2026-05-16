// Ports/Environment+ResourceInspector.swift — app_shell bounded context
// DDD role: SwiftUI environment integration for ResourceInspectorViewModel
// ADR ref: ADR-0073 (inspector trailing column substitutes resource detail tabs)

import SwiftUI

// MARK: - EnvironmentKey

private struct ResourceInspectorViewModelKey: EnvironmentKey {
    /// Default is `nil` — callers that need the view model must receive it from
    /// a parent that injected one (via `AppShellDependencies`). This avoids the
    /// Swift 6 strict-concurrency restriction on calling a `@MainActor init`
    /// from a nonisolated `EnvironmentKey.defaultValue` static property.
    ///
    /// Consistent with the `OpenTabsActorKey` pattern in `OpenTabsKey.swift`.
    static let defaultValue: ResourceInspectorViewModel? = nil
}

// MARK: - EnvironmentValues extension

public extension EnvironmentValues {
    /// The `ResourceInspectorViewModel` driving the Inspector trailing column,
    /// or `nil` when the Inspector is not wired (previews, tests, menu bar scene).
    ///
    /// Consumed by:
    /// - `ResourceInspectorPanel` — renders `selectedKey` content.
    /// - Resource list views — call `setSelection(_:)` on row tap.
    ///
    /// Access with:
    /// ```swift
    /// @Environment(\.resourceInspector) private var inspector
    /// ```
    var resourceInspector: ResourceInspectorViewModel? {
        get { self[ResourceInspectorViewModelKey.self] }
        set { self[ResourceInspectorViewModelKey.self] = newValue }
    }
}

// MARK: - View extension convenience

public extension View {
    /// Injects a `ResourceInspectorViewModel` into the SwiftUI environment tree.
    ///
    /// Called once at the scene root (`AppShellView.body`) so every list view
    /// in the hierarchy resolves the same instance. Accepts an optional so the
    /// composition root can pass `deps.inspectorViewModel` directly without
    /// unwrapping — when `nil`, the existing environment value is unchanged.
    func resourceInspector(_ viewModel: ResourceInspectorViewModel?) -> some View {
        environment(\.resourceInspector, viewModel)
    }
}
