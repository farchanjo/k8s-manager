// Ports/Dependencies.swift — app_shell bounded context
// DDD role: Dependency key registry + Unimplemented defaults
// ADR ref: ADR-0050 (tab system — openTabsActor)

// MARK: - AppShellDependencies

/// Centralised registry of all port dependencies for the `app_shell` bounded context.
///
/// Injected at the composition root; never constructed from within domain types.
public struct AppShellDependencies: Sendable {
    public let translationCatalog: any TranslationCatalogPort
    public let toastEmitter: any ToastEmitterPort
    public let localePreference: any LocalePreferencePort
    /// Tab-state actor for the currently active cluster, or `nil` when no
    /// cluster session is in progress (ADR-0050).
    ///
    /// Production initialisation:
    /// ```swift
    /// OpenTabsActor(persistenceURL:
    ///     ApplicationPaths.clusterStateRoot
    ///         .appendingPathComponent("\(clusterId.rawValue)/open-tabs.json"))
    /// ```
    public let openTabsActor: OpenTabsActor?
    /// Workspace-scoped tabs actor — owns the persistent Welcome tab and any
    /// future workspace-level surfaces (ADR-0054). Single instance per launch.
    /// `nil` only in previews/tests that do not exercise the Welcome flow.
    public let workspaceTabsActor: WorkspaceTabsActor?
    /// Per-window navigation history actor (ADR-0065). Owns the back/forward
    /// deque and exposes keyboard-shortcut entry points. `nil` only in
    /// previews/tests that do not exercise the navigation-history flow.
    public let navigationHistoryActor: NavigationHistoryActor?
    /// Code editor port (YAML/JSON/MD highlighting) — ADR-0030.
    /// Composition root injects `CodeEditorViewAdapter`; AppShell never imports
    /// the adapter target directly to preserve the ADR-0020 invariant.
    public let codeEditor: any CodeEditorPort

    public init(
        translationCatalog: any TranslationCatalogPort,
        toastEmitter: any ToastEmitterPort,
        localePreference: any LocalePreferencePort,
        openTabsActor: OpenTabsActor? = nil,
        workspaceTabsActor: WorkspaceTabsActor? = nil,
        navigationHistoryActor: NavigationHistoryActor? = nil,
        codeEditor: any CodeEditorPort = UnimplementedCodeEditor()
    ) {
        self.translationCatalog = translationCatalog
        self.toastEmitter = toastEmitter
        self.localePreference = localePreference
        self.openTabsActor = openTabsActor
        self.workspaceTabsActor = workspaceTabsActor
        self.navigationHistoryActor = navigationHistoryActor
        self.codeEditor = codeEditor
    }

    // MARK: - Unimplemented defaults

    /// Returns a `fatal`-on-use dependency set suitable for use in previews and tests
    /// that need to override only a subset of ports.
    public static var unimplemented: AppShellDependencies {
        AppShellDependencies(
            translationCatalog: UnimplementedTranslationCatalog(),
            toastEmitter: UnimplementedToastEmitter(),
            localePreference: UnimplementedLocalePreferenceStore(),
            codeEditor: UnimplementedCodeEditor()
        )
    }
}

// MARK: - UnimplementedCodeEditor

import SwiftUI

/// Stand-in `CodeEditorPort` for previews/tests; aborts on use so missing wiring
/// at composition root surfaces immediately. Production code receives a real
/// `CodeEditorViewAdapter` instance via dependency injection.
public struct UnimplementedCodeEditor: CodeEditorPort, Sendable {
    public init() {}

    @MainActor
    public func makeEditor(initial: String, language: EditorLanguage, theme: EditorTheme) -> AnyView {
        preconditionFailure("CodeEditorPort not implemented — inject CodeEditorViewAdapter at composition root")
    }

    public func editStream() -> AsyncStream<EditEvent> {
        AsyncStream { continuation in continuation.finish() }
    }
}

// MARK: - Unimplemented stubs

private struct UnimplementedTranslationCatalog: TranslationCatalogPort, Sendable {
    func translate(key: String, locale: String) -> String {
        preconditionFailure("TranslationCatalogPort not implemented — inject a real dependency")
    }

    func translatePlural(key: String, count: Int, locale: String) -> String {
        preconditionFailure("TranslationCatalogPort not implemented — inject a real dependency")
    }
}

private struct UnimplementedToastEmitter: ToastEmitterPort, Sendable {
    func emit(
        title: String, message: String?, severity: ToastDomainSeverity,
        iconSymbolName: String?, pinned: Bool, action: ToastDomainAction?
    ) async {
        preconditionFailure("ToastEmitterPort not implemented — inject a real dependency")
    }
}

private actor UnimplementedLocalePreferenceStore: LocalePreferencePort {
    func load() async throws -> LocalePreference {
        preconditionFailure("LocalePreferencePort not implemented — inject a real dependency")
    }

    func save(_ preference: LocalePreference) async throws {
        preconditionFailure("LocalePreferencePort not implemented — inject a real dependency")
    }
}
