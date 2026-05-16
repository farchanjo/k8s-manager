// CodeEditorAdapter.swift — module namespace marker
// Real implementation: CodeEditorViewAdapter.swift
// ADR-0030: CodeEditorView (Tier B, mchakravarty/CodeEditorView)
import Foundation

/// Namespace marker for the `CodeEditorAdapter` module.
///
/// The concrete implementation lives in ``CodeEditorViewAdapter``.
public enum CodeEditorAdapter: Sendable {
    /// Semantic version for the adapter module.
    public static let moduleVersion = "0.1.0"
}
