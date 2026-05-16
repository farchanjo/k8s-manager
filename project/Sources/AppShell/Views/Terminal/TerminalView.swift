// Views/Terminal/TerminalView.swift — app_shell bounded context
// DDD role: View — NSTextView-based terminal emulator wrapper
// ADR ref: ADR-0017 (terminal sessions), ADR-0001 (macOS 14+ native)

import SwiftUI
import AppKit

// MARK: - TerminalView

/// `NSTextView`-backed terminal display embedded in SwiftUI via `NSViewRepresentable`.
///
/// Displays accumulated `output` text in a monospaced font on a dark background.
/// Keyboard events are captured and forwarded via `onInput`. Terminal dimensions
/// are measured from the view's geometry and reported via `onResize`.
///
/// ANSI colour CSI sequences (`ESC[...m`) are stripped for v1; plain text only.
/// Full ANSI rendering is a future enhancement (SwiftTerm library integration).
public struct TerminalView: NSViewRepresentable {

    // MARK: Properties

    /// Accumulated terminal output (stdout + stderr).
    public let output: String
    /// Called when the user types input to be sent to the remote process.
    public let onInput: @MainActor (String) -> Void
    /// Called when the measured terminal size changes (cols, rows).
    public let onResize: @MainActor (Int, Int) -> Void
    /// Font family used for the terminal text.
    public let fontFamily: String
    /// Font size in points.
    public let fontSize: Double

    // MARK: Init

    public init(
        output: String,
        onInput: @escaping @MainActor (String) -> Void,
        onResize: @escaping @MainActor (Int, Int) -> Void,
        fontFamily: String = "SF Mono",
        fontSize: Double = 13
    ) {
        self.output = output
        self.onInput = onInput
        self.onResize = onResize
        self.fontFamily = fontFamily
        self.fontSize = fontSize
    }

    // MARK: NSViewRepresentable

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = buildScrollView()
        let textView = buildTextView(context: context)
        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? TerminalNSTextView else { return }
        let stripped = Self.stripAnsi(output)
        if textView.string != stripped {
            textView.string = stripped
            textView.scrollToEndOfDocument(nil)
        }
        updateDimensions(textView: textView, scrollView: nsView)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput)
    }

    // MARK: Private helpers

    private func buildScrollView() -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.backgroundColor = .black
        return sv
    }

    private func buildTextView(context: Context) -> TerminalNSTextView {
        let tv = TerminalNSTextView()
        tv.font = resolvedFont()
        tv.isEditable = true
        tv.isSelectable = true
        tv.backgroundColor = .black
        tv.textColor = NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.2, alpha: 1.0)
        tv.insertionPointColor = .green
        tv.drawsBackground = true
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.delegate = context.coordinator
        tv.onInput = onInput
        return tv
    }

    private func resolvedFont() -> NSFont {
        NSFont(name: fontFamily, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private func updateDimensions(textView: NSTextView, scrollView: NSScrollView) {
        let font = resolvedFont()
        let charW = font.advancement(forGlyph: font.glyph(withName: "M")).width
        let rowH  = font.boundingRectForFont.height
        guard charW > 0, rowH > 0 else { return }
        let visibleW = scrollView.contentSize.width
        let visibleH = scrollView.contentSize.height
        let cols = max(1, Int(visibleW / charW))
        let rows = max(1, Int(visibleH / rowH))
        onResize(cols, rows)
    }

    // MARK: ANSI stripping (v1 minimal)

    /// Strips CSI colour sequences (`ESC [ ... m`) from the text, preserving
    /// `\n`, `\r`, and `\t`. Full ANSI rendering is a future enhancement.
    static func stripAnsi(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var iter = text.unicodeScalars.makeIterator()
        while let ch = iter.next() {
            if ch == "\u{1B}" {
                guard let next = iter.next() else { break }
                if next == "[" {
                    while let seq = iter.next(), seq != "m" { /* skip */ }
                }
                // else: other escape sequence — skip the following char
            } else {
                result.unicodeScalars.append(ch)
            }
        }
        return result
    }

    // MARK: - Coordinator

    /// Bridges `NSTextViewDelegate` events back into the SwiftUI closure.
    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {

        let onInput: @MainActor (String) -> Void

        init(onInput: @escaping @MainActor (String) -> Void) {
            self.onInput = onInput
        }

        public func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            // Let TerminalNSTextView.keyDown handle all input.
            return false
        }
    }
}

// MARK: - TerminalNSTextView

/// `NSTextView` subclass that captures key events and routes them to the
/// exec session rather than the standard text editing system.
final class TerminalNSTextView: NSTextView {

    var onInput: (@MainActor (String) -> Void)?

    override func keyDown(with event: NSEvent) {
        // Handle Ctrl+C / Ctrl+D as special control bytes.
        if event.modifierFlags.contains(.control) {
            if let chars = event.characters, chars == "c" {
                routeInput("\u{03}")  // ETX
                return
            }
            if let chars = event.characters, chars == "d" {
                routeInput("\u{04}")  // EOT
                return
            }
        }
        // Forward printable characters and special keys.
        if let chars = event.characters, !chars.isEmpty {
            routeInput(chars)
        } else {
            super.keyDown(with: event)
        }
    }

    private func routeInput(_ text: String) {
        let handler = onInput
        Task { @MainActor in handler?(text) }
    }
}
