// Ports/Environment+AppShellDependencies.swift — app_shell bounded context
// DDD role: SwiftUI environment integration for AppShellDependencies
// ADR ref: ADR-0005 (app_shell bounded context), ADR-0020 (composition root)
//
// Pattern: EnvironmentKey — wired once at the root scene; consumed via
// @Environment(\.appShellDependencies) in any descendant view or view model.

import SwiftUI

// MARK: - EnvironmentKey

private struct AppShellDependenciesKey: EnvironmentKey {
    /// Default is `.unimplemented` — `preconditionFailure` guards catch any
    /// call site that forgets to inject real dependencies at the composition root.
    static let defaultValue: AppShellDependencies = .unimplemented
}

// MARK: - EnvironmentValues extension

public extension EnvironmentValues {
    /// The `AppShellDependencies` registry injected by the composition root.
    ///
    /// Access via `@Environment(\.appShellDependencies) private var deps`
    /// in any `View` or `@MainActor` type that is part of the SwiftUI view tree.
    var appShellDependencies: AppShellDependencies {
        get { self[AppShellDependenciesKey.self] }
        set { self[AppShellDependenciesKey.self] = newValue }
    }
}

// MARK: - View modifier convenience

public extension View {
    /// Injects the given `AppShellDependencies` into the SwiftUI environment
    /// for all descendant views.
    ///
    /// Call once at the scene root — for example:
    /// ```swift
    /// AppShellView(...)
    ///     .appShellDependencies(AppShellDependencies(
    ///         translationCatalog: BundleTranslationCatalog(),
    ///         toastEmitter: ToastDomainEmitter(aggregate: toastAggregate),
    ///         localePreference: InMemoryLocalePreferenceStore()
    ///     ))
    /// ```
    func appShellDependencies(_ deps: AppShellDependencies) -> some View {
        environment(\.appShellDependencies, deps)
    }
}

// MARK: - Scene modifier convenience

public extension Scene {
    /// Injects the given `AppShellDependencies` into the SwiftUI environment
    /// for all descendant views within a `Scene`.
    ///
    /// Use on `MenuBarExtra` and other `Scene` types that are not `View` subtypes:
    /// ```swift
    /// K8sManagerMenuBarScene()
    ///     .appShellDependencies(appShellDeps)
    /// ```
    func appShellDependencies(_ deps: AppShellDependencies) -> some Scene {
        environment(\.appShellDependencies, deps)
    }
}
