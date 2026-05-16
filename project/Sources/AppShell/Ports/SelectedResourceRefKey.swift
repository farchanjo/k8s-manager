// Ports/SelectedResourceRefKey.swift — app_shell bounded context
// DDD role: SwiftUI EnvironmentKey for resource selection propagation
// ADR ref: ADR-0021 (detail drawer — inspector wiring), ADR-0050 (tab system)

import SwiftUI

// MARK: - EnvironmentKey

/// Environment-injected closure used by resource list views to signal that
/// the operator selected (or cleared) a `ResourceRef`.
///
/// The receiver (typically `ActiveTabContentView`) stores the ref in local
/// `@State` so the inspector drawer (`ResourceDetailDrawer`) can present
/// itself without each list view needing to re-implement drawer lifecycle.
///
/// Pass `nil` to clear the selection (e.g. when no row is selected).
private struct OnResourceSelectKey: EnvironmentKey {
    static let defaultValue: @Sendable @MainActor (ResourceRef?) -> Void = { _ in }
}

// MARK: - EnvironmentValues extension

public extension EnvironmentValues {
    /// Callback invoked by list views when their row selection changes.
    ///
    /// Read with `@Environment(\.onResourceSelect) private var onResourceSelect`
    /// and call inside `.onChange(of: viewModel.selectedId)` to lift selection
    /// up to the surrounding tab content view.
    var onResourceSelect: @Sendable @MainActor (ResourceRef?) -> Void {
        get { self[OnResourceSelectKey.self] }
        set { self[OnResourceSelectKey.self] = newValue }
    }
}
