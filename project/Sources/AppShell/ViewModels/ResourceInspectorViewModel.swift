// ViewModels/ResourceInspectorViewModel.swift — app_shell bounded context
// DDD role: View model — Inspector panel state + visibility
// ADR ref: ADR-0073 (inspector trailing column substitutes resource detail tabs)
//          ADR-0034 (state-driven realtime UI — @Observable + @MainActor)

import Observation
import SwiftUI

// MARK: - ResourceInspectorViewModel

/// `@Observable` view model driving the Inspector trailing column.
///
/// Owns two pieces of state:
/// - `selectedKey` — which resource instance is currently shown (nil = empty state).
/// - `isVisible` — whether the Inspector column is revealed.
///
/// All mutations run on `@MainActor` per ADR-0034 and ADR-0073 §"Swift 6
/// strict concurrency". The view model is created once at the composition root
/// (via `AppShellDependencies`) and distributed through the SwiftUI environment.
///
/// In Wave 3, the view model exposes `selectedKey` directly to
/// `ResourceInspectorPanel`, which dispatches to `ResourceInspectorContent`
/// providers for rendering. Per-kind async watch subscriptions are deferred to
/// subsequent waves; the panel itself handles the `@Observable` reactivity.
@Observable
@MainActor
public final class ResourceInspectorViewModel {

    // MARK: Observable state

    /// Identity of the resource currently shown in the Inspector.
    ///
    /// Setting this to a non-nil value makes the Inspector content area
    /// update reactively. Setting it to `nil` shows the empty state.
    public var selectedKey: InspectorKey?

    /// Whether the Inspector trailing column is currently presented.
    ///
    /// Bound to `.inspector(isPresented:)` on the canvas. Defaults to
    /// `false` per ADR-0073 §"Inspector visibility — Default state: closed".
    public var isVisible: Bool = false

    // MARK: Init

    /// Designated initialiser. No dependencies required in Wave 3;
    /// subsequent waves inject `KubernetesApiPort` for async watch subscriptions.
    public init() {}

    // MARK: Entry points

    /// Updates the selected resource and surfaces the Inspector if it was hidden.
    ///
    /// Called by list views when a row is tapped (ADR-0073 §"Row tap routing").
    /// If the Inspector is already visible this is a no-op for `isVisible`.
    ///
    /// - Parameter key: Identity of the tapped resource row, or `nil` to clear.
    public func setSelection(_ key: InspectorKey?) {
        selectedKey = key
        if key != nil && !isVisible {
            isVisible = true
        }
    }

    /// Toggles `isVisible`.
    ///
    /// Bound to the `⌘⌥0` keyboard shortcut (ADR-0073 §"Inspector visibility")
    /// and to the toolbar toggle button.
    public func toggle() {
        isVisible.toggle()
    }
}
