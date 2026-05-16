// CodeEditorViewAdapter.swift — CodeEditorPort implementation backed by mchakravarty/CodeEditorView
// Adapter layer; bridges the Tier B library to the AppShell port (ADR-0030, ADR-0019).
//
// Concurrency model (ADR-0011):
//   - `CodeEditorViewAdapter` is a `@MainActor`-isolated `final class`; all editor state
//     lives on the main actor to satisfy both SwiftUI binding semantics and the
//     `@preconcurrency import CodeEditorView` Tier B boundary.
//   - `editStream()` is `nonisolated` and safe to call from any context; the
//     `AsyncStream.Continuation` is captured safely via `@Sendable` closure.
@preconcurrency import CodeEditorView
import AppShell
import SwiftUI
import Foundation
import LanguageSupport

// MARK: - CodeEditorViewAdapter

/// Infrastructure adapter implementing ``CodeEditorPort`` via `mchakravarty/CodeEditorView`.
///
/// One adapter instance corresponds to one editor session. Creating a new instance
/// resets both the text binding and the edit-event stream.
///
/// ### Language mapping
/// `CodeEditorView` 0.15.x ships grammars for Swift, Haskell, Cypher, and SQLite.
/// YAML / JSON / Markdown grammars ship starting in 2.x. Until the version pin in
/// `Package.swift` is updated to ≥ 2.0, these languages fall back to `.none`
/// (plain-text tokenisation with no highlighting). The mapping table is ready to
/// accept the grammar factories once the dependency is bumped.
///
/// ### Thread safety
/// `@MainActor` isolation is declared on the class; `editStream()` is `nonisolated`
/// and returns a `Sendable` value, satisfying Swift 6 strict concurrency.
@MainActor
public final class CodeEditorViewAdapter: CodeEditorPort {

    // MARK: State

    /// The live text binding shared between the editor view and the stream bridge.
    private var text: String

    /// Initial text used to compute the `dirty` flag on each edit event.
    private var initialText: String

    /// Editor position state (cursor + scroll); held here to avoid recreating the view.
    private var position: CodeEditor.Position = .init()

    /// Messages / diagnostics displayed in the editor gutter.
    private var messages: Set<TextLocated<Message>> = []

    /// Continuation driving the ``editStream()`` `AsyncStream`.
    private var continuation: AsyncStream<EditEvent>.Continuation?

    // MARK: Init

    /// Creates a new adapter. Called by the composition root during dependency injection.
    public init() {
        self.text = ""
        self.initialText = ""
    }

    // MARK: CodeEditorPort

    /// Constructs the `CodeEditor` SwiftUI view wrapped in `AnyView`.
    ///
    /// Calling this method a second time on the same adapter instance replaces the
    /// current session (text and stream are reset).
    @MainActor
    public func makeEditor(
        initial: String,
        language: EditorLanguage,
        theme: EditorTheme
    ) -> AnyView {
        // Reset session state.
        text = initial
        initialText = initial
        position = .init()
        messages = []

        let languageConfig = languageConfiguration(for: language)
        let editorTheme = resolvedTheme(for: theme)

        let view = EditorView(
            text: bindingForText(),
            position: Binding(get: { self.position }, set: { self.position = $0 }),
            messages: Binding(get: { self.messages }, set: { self.messages = $0 }),
            language: languageConfig,
            theme: editorTheme
        )
        return AnyView(view)
    }

    /// Returns an `AsyncStream` emitting one ``EditEvent`` per keystroke / paste.
    ///
    /// The stream is finished when the adapter is deallocated or when a new
    /// `makeEditor` call is made (which replaces the continuation).
    nonisolated public func editStream() -> AsyncStream<EditEvent> {
        // Move back to MainActor to touch `self.continuation`.
        AsyncStream { continuation in
            Task { @MainActor in
                // Finish any previous stream before assigning the new continuation.
                self.continuation?.finish()
                self.continuation = continuation
                continuation.onTermination = { @Sendable [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if self.continuation === continuation {
                            self.continuation = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: Internal helpers

    /// Creates a `Binding<String>` that mirrors `self.text` and emits an ``EditEvent``
    /// on every set call.
    private func bindingForText() -> Binding<String> {
        Binding(
            get: { self.text },
            set: { [weak self] newValue in
                guard let self else { return }
                self.text = newValue
                let event = EditEvent(
                    content: newValue,
                    dirty: newValue != self.initialText
                )
                self.continuation?.yield(event)
            }
        )
    }

    /// Maps ``EditorLanguage`` to `LanguageConfiguration`.
    ///
    /// Once `Package.swift` pins `CodeEditorView` to ≥ 2.0, replace the `.none`
    /// fallbacks with the proper factory calls (e.g. `.yaml()`, `.json()`, `.markdown()`).
    private func languageConfiguration(for language: EditorLanguage) -> LanguageConfiguration {
        switch language {
        case .yaml:
            // TODO(ADR-0030): Replace with `.yaml()` when CodeEditorView ≥ 2.0 is pinned.
            return .none
        case .json:
            // TODO(ADR-0030): Replace with `.json()` when CodeEditorView ≥ 2.0 is pinned.
            return .none
        case .markdown:
            // TODO(ADR-0030): Replace with `.markdown()` when CodeEditorView ≥ 2.0 is pinned.
            return .none
        case .plainText:
            return .none
        }
    }

    /// Resolves ``EditorTheme`` to a `CodeEditorView` `Theme`.
    ///
    /// `EditorTheme.system` defers to `NSApp.effectiveAppearance` at call time,
    /// falling back to `defaultLight`.
    private func resolvedTheme(for theme: EditorTheme) -> Theme {
        switch theme {
        case .light:
            return .defaultLight
        case .dark:
            return .defaultDark
        case .system:
#if os(macOS)
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? .defaultDark : .defaultLight
#else
            return .defaultLight
#endif
        }
    }
}

// MARK: - EditorView (internal SwiftUI shell)

/// Internal SwiftUI wrapper that applies the theme via environment and renders `CodeEditor`.
///
/// Kept private to this file; callers interact only through ``CodeEditorViewAdapter``.
private struct EditorView: View {
    @Binding var text: String
    @Binding var position: CodeEditor.Position
    @Binding var messages: Set<TextLocated<Message>>
    let language: LanguageConfiguration
    let theme: Theme

    var body: some View {
        CodeEditor(
            text: $text,
            position: $position,
            messages: $messages,
            language: language
        )
        .environment(\.codeEditorTheme, theme)
    }
}
