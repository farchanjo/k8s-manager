// CodeEditorPort.swift — AppShell port for an embeddable code editor component
// Bounded context: app_shell (owns SwiftUI surface; resource_browser domain stays SwiftUI-free)
// ADR-0030: CodeEditorView is the chosen Tier B library for YAML/JSON/Markdown editing.
//
// Design note:
//   AnyView is SwiftUI-only, so the port lives in AppShell (which already imports SwiftUI)
//   rather than ResourceBrowser. Adapters in the infrastructure layer (CodeEditorAdapter)
//   implement this protocol and inject it at the composition root.
import SwiftUI

// MARK: - EditorLanguage

/// Supported language modes for the code editor.
///
/// Maps 1:1 to the grammar selections available via `CodeEditorView`'s
/// `LanguageConfiguration`. Extend as new grammars are bundled.
public enum EditorLanguage: String, Sendable, CaseIterable {
    /// YAML — primary format for Kubernetes manifests (ADR-0030).
    case yaml
    /// JSON — used by automation toolchains and raw Kubernetes API responses.
    case json
    /// Markdown — README files embedded in Helm chart ConfigMaps and wiki content.
    case markdown
    /// Plain text — fallback when no grammar matches.
    case plainText
}

// MARK: - EditorTheme

/// Colour scheme preference passed to the code editor.
public enum EditorTheme: String, Sendable, CaseIterable {
    /// Force light appearance regardless of system setting.
    case light
    /// Force dark appearance regardless of system setting.
    case dark
    /// Follow the active system appearance (default).
    case system
}

// MARK: - EditEvent

/// Value emitted by ``CodeEditorPort/editStream()`` on every text change.
public struct EditEvent: Sendable {
    /// Current editor text after the change.
    public let content: String
    /// `true` when the editor text differs from the initial content passed to ``CodeEditorPort/makeEditor(initial:language:theme:)``.
    public let dirty: Bool

    /// Memberwise initialiser.
    public init(content: String, dirty: Bool) {
        self.content = content
        self.dirty = dirty
    }
}

// MARK: - CodeEditorPort

/// Abstraction for a syntax-highlighting code editor component (ADR-0030).
///
/// Adopters (e.g. `CodeEditorViewAdapter`) wrap `mchakravarty/CodeEditorView`
/// and bridge text changes into ``editStream()``. The protocol lives in `AppShell`
/// because its return type (`AnyView`) requires SwiftUI — a dependency that domain
/// cores such as `ResourceBrowser` must not take.
///
/// ### Usage
/// ```swift
/// let editor = adapter.makeEditor(initial: manifest, language: .yaml, theme: .system)
/// for await event in adapter.editStream() {
///     if event.dirty { handleChange(event.content) }
/// }
/// ```
public protocol CodeEditorPort: Sendable {

    /// Creates a SwiftUI view presenting an interactive code editor.
    ///
    /// - Parameters:
    ///   - initial: The starting text content.
    ///   - language: Grammar/syntax mode for highlighting.
    ///   - theme: Colour scheme applied to the editor surface.
    /// - Returns: An opaque SwiftUI view wrapping the underlying editor component.
    @MainActor
    func makeEditor(initial: String, language: EditorLanguage, theme: EditorTheme) -> AnyView

    /// An `AsyncStream` that yields one ``EditEvent`` per text change.
    ///
    /// The stream is backed by the same binding that drives the editor view returned
    /// by ``makeEditor(initial:language:theme:)``. It terminates when the adapter is
    /// deallocated. Callers should cancel iteration on view disappearance.
    func editStream() -> AsyncStream<EditEvent>
}
