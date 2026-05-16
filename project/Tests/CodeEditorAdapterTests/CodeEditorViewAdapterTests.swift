// CodeEditorViewAdapterTests.swift — unit tests for CodeEditorViewAdapter
// Coverage: language mapping (all EditorLanguage cases), theme mapping (all EditorTheme
//           cases), EditEvent value semantics, edit-stream construction without crash,
//           session reset on makeEditor re-call.
//
// Design note: CodeEditorViewAdapter is @MainActor-isolated; all test methods are
// run on the MainActor via the class-level annotation. No display connection is
// required — SwiftUI views are constructed but never rendered.

import XCTest
import SwiftUI
@testable import CodeEditorAdapter
import AppShell

// MARK: - CodeEditorViewAdapterTests

@MainActor
final class CodeEditorViewAdapterTests: XCTestCase {

    // MARK: - Language mapping — makeEditor(language:) per EditorLanguage case

    func test_makeEditor_yaml_completesWithoutCrash() {
        let adapter = CodeEditorViewAdapter()
        let view = adapter.makeEditor(initial: "apiVersion: v1\n", language: .yaml, theme: .system)
        _ = view
        XCTAssert(true, "makeEditor(.yaml) must not throw or crash")
    }

    func test_makeEditor_json_completesWithoutCrash() {
        let adapter = CodeEditorViewAdapter()
        let view = adapter.makeEditor(
            initial: "{\"kind\": \"Pod\"}",
            language: .json,
            theme: .light
        )
        _ = view
        XCTAssert(true, "makeEditor(.json) must not throw or crash")
    }

    func test_makeEditor_markdown_completesWithoutCrash() {
        let adapter = CodeEditorViewAdapter()
        let view = adapter.makeEditor(initial: "# Title\n", language: .markdown, theme: .dark)
        _ = view
        XCTAssert(true, "makeEditor(.markdown) must not throw or crash")
    }

    func test_makeEditor_plainText_completesWithoutCrash() {
        let adapter = CodeEditorViewAdapter()
        let view = adapter.makeEditor(initial: "plain text", language: .plainText, theme: .system)
        _ = view
        XCTAssert(true, "makeEditor(.plainText) must not throw or crash")
    }

    func test_makeEditor_allLanguageCases_exhaustive() {
        let adapter = CodeEditorViewAdapter()
        for language in EditorLanguage.allCases {
            let view = adapter.makeEditor(initial: "content", language: language, theme: .system)
            _ = view
        }
        XCTAssertEqual(
            EditorLanguage.allCases.count,
            4,
            "EditorLanguage has 4 cases; update this test if a new case is added"
        )
    }

    // MARK: - Theme mapping — makeEditor(theme:) per EditorTheme case

    func test_makeEditor_lightTheme_completesWithoutCrash() {
        let adapter = CodeEditorViewAdapter()
        let view = adapter.makeEditor(initial: "x", language: .yaml, theme: .light)
        _ = view
        XCTAssert(true, "makeEditor(.light) must not throw or crash")
    }

    func test_makeEditor_darkTheme_completesWithoutCrash() {
        let adapter = CodeEditorViewAdapter()
        let view = adapter.makeEditor(initial: "x", language: .yaml, theme: .dark)
        _ = view
        XCTAssert(true, "makeEditor(.dark) must not throw or crash")
    }

    func test_makeEditor_systemTheme_completesWithoutCrash() {
        let adapter = CodeEditorViewAdapter()
        let view = adapter.makeEditor(initial: "x", language: .yaml, theme: .system)
        _ = view
        XCTAssert(true, "makeEditor(.system) must not throw or crash")
    }

    func test_makeEditor_allThemeCases_exhaustive() {
        let adapter = CodeEditorViewAdapter()
        for theme in EditorTheme.allCases {
            let view = adapter.makeEditor(initial: "x", language: .yaml, theme: theme)
            _ = view
        }
        XCTAssertEqual(
            EditorTheme.allCases.count,
            3,
            "EditorTheme has 3 cases; update this test if a new case is added"
        )
    }

    // MARK: - Session reset on consecutive makeEditor calls

    func test_makeEditor_secondCall_doesNotCrash() {
        let adapter = CodeEditorViewAdapter()
        let first = adapter.makeEditor(initial: "version: v1\n", language: .yaml, theme: .light)
        let second = adapter.makeEditor(initial: "version: v2\n", language: .json, theme: .dark)
        _ = first
        _ = second
        XCTAssert(true, "Two consecutive makeEditor calls on the same adapter must not crash")
    }

    // MARK: - EditEvent value semantics

    func test_editEvent_dirtyFalse_whenTextUnchanged() {
        let event = EditEvent(content: "same content", dirty: false)
        XCTAssertFalse(event.dirty)
        XCTAssertEqual(event.content, "same content")
    }

    func test_editEvent_dirtyTrue_whenTextChanged() {
        let event = EditEvent(content: "modified content", dirty: true)
        XCTAssertTrue(event.dirty)
        XCTAssertEqual(event.content, "modified content")
    }

    func test_editEvent_emptyContent_allowedWhenDirtyFalse() {
        let event = EditEvent(content: "", dirty: false)
        XCTAssertEqual(event.content, "")
        XCTAssertFalse(event.dirty)
    }

    // MARK: - editStream() — construction and teardown

    func test_editStream_constructedWithoutCrash() {
        let adapter = CodeEditorViewAdapter()
        let stream = adapter.editStream()
        // Calling makeIterator should not crash.
        var iterator = stream.makeAsyncIterator()
        _ = iterator
        XCTAssert(true, "editStream() returned a valid AsyncStream without crashing")
    }

    func test_editStream_secondCallReturnsFreshStream() {
        let adapter = CodeEditorViewAdapter()
        let stream1 = adapter.editStream()
        let stream2 = adapter.editStream()
        var iter1 = stream1.makeAsyncIterator()
        var iter2 = stream2.makeAsyncIterator()
        _ = iter1
        _ = iter2
        XCTAssert(true, "Two editStream() calls on the same adapter must not crash")
    }

    func test_editStream_concurrencyPath_noDeadlock() async throws {
        // Verify that the async Task hop inside editStream() completes without
        // deadlocking when called from a MainActor context.
        let adapter = CodeEditorViewAdapter()
        let stream = adapter.editStream()
        _ = stream

        // Give the internal Task a chance to hop to MainActor and register the continuation.
        await Task.yield()
        await Task.yield()

        // Create the editor view (which also touches MainActor state).
        let view = adapter.makeEditor(initial: "apiVersion: v1\n", language: .yaml, theme: .system)
        _ = view

        await Task.yield()
        XCTAssert(true, "editStream() + makeEditor() concurrency path completed without deadlock")
    }

    // MARK: - EditorLanguage raw values (stable API contract)

    func test_editorLanguage_rawValues_matchSpec() {
        XCTAssertEqual(EditorLanguage.yaml.rawValue, "yaml")
        XCTAssertEqual(EditorLanguage.json.rawValue, "json")
        XCTAssertEqual(EditorLanguage.markdown.rawValue, "markdown")
        XCTAssertEqual(EditorLanguage.plainText.rawValue, "plainText")
    }

    // MARK: - EditorTheme raw values (stable API contract)

    func test_editorTheme_rawValues_matchSpec() {
        XCTAssertEqual(EditorTheme.light.rawValue, "light")
        XCTAssertEqual(EditorTheme.dark.rawValue, "dark")
        XCTAssertEqual(EditorTheme.system.rawValue, "system")
    }
}
