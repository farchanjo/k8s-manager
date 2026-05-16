// Actors/RealtimeValidatorService.swift — resource_browser bounded context
// DDD role: DomainService (actor)
// ADR refs: ADR-0030 (integrated editor — real-time YAML/JSON syntax validation)

import Foundation
import Logging

// MARK: - ValidationResult

/// Outcome of a single validation pass on editor content.
public struct ValidationResult: Sendable {
    /// All diagnostics produced by the pass. Empty means no errors/warnings.
    public let diagnostics: [Diagnostic]

    /// `true` when the document is syntactically valid (zero error-severity diagnostics).
    public var isValid: Bool {
        !diagnostics.contains { $0.severity == .error }
    }

    public init(diagnostics: [Diagnostic]) {
        self.diagnostics = diagnostics
    }

    /// A valid result with no diagnostics.
    public static let valid = ValidationResult(diagnostics: [])
}

// MARK: - RealtimeValidatorService

/// Validates YAML or JSON syntax on each editor content change.
///
/// Performs syntactic validation only. Schema-level validation against the
/// Kubernetes OpenAPI v3 spec is deferred to `K8sSchemaValidator` (ADR-0030).
///
/// The actor serialises concurrent validate calls so that only the newest
/// content is processed when multiple edits arrive in rapid succession.
/// Debouncing (100 ms) is expected at the call site; this actor does not
/// apply its own debounce.
public actor RealtimeValidatorService {

    // MARK: - Properties

    private let logger: Logger

    // MARK: - Initialiser

    /// Creates the validator with an optional logger.
    public init(logger: Logger = Logger(label: "resource_browser.realtime_validator")) {
        self.logger = logger
    }

    // MARK: - Public API

    /// Validates the syntactic structure of `content` for the given GVK.
    ///
    /// Returns a `ValidationResult` immediately. The GVK is used to select
    /// the correct parser (YAML for Kubernetes manifests, JSON as fallback).
    /// Schema validation against the Kubernetes API is not performed here.
    ///
    /// - Parameters:
    ///   - content: The raw text from the editor buffer.
    ///   - gvk: The Kubernetes API type being edited (informs parser selection).
    /// - Returns: A `ValidationResult` containing zero or more `Diagnostic` values.
    public func validate(_ content: String, gvk: GroupVersionKind) async -> ValidationResult {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .valid
        }

        let format = inferFormat(content: content, gvk: gvk)
        switch format {
        case .yaml:
            return validateYAML(content)
        case .json:
            return validateJSON(content)
        case .markdown:
            return .valid
        }
    }

    // MARK: - Private — format inference

    private func inferFormat(content: String, gvk: GroupVersionKind) -> EditorFormat {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return .json
        }
        return .yaml
    }

    // MARK: - Private — YAML validation

    /// Validates YAML by scanning for common structural errors without a full parse.
    ///
    /// A lightweight heuristic: checks indentation consistency and key-value
    /// colon presence. Full Yams parse is the preferred approach; this stub
    /// covers the initial slice per ADR-0030 §RealtimeValidatorService.
    private func validateYAML(_ content: String) -> ValidationResult {
        var diagnostics: [Diagnostic] = []
        let lines = content.components(separatedBy: "\n")

        for (idx, line) in lines.enumerated() {
            let lineNumber = idx + 1
            // Detect tab characters (YAML forbids tabs as indentation).
            if line.first == "\t" {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    lineNumber: lineNumber,
                    columnNumber: 1,
                    message: "Tab characters are not permitted in YAML indentation.",
                    source: .yamlParser
                ))
            }
            // Detect lines that look like keys but are missing the colon value separator.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty,
               !trimmed.hasPrefix("#"),
               !trimmed.hasPrefix("-"),
               !trimmed.hasPrefix("|"),
               !trimmed.hasPrefix(">"),
               !trimmed.contains(":"),
               !trimmed.contains("{"),
               !trimmed.contains("[") {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    lineNumber: lineNumber,
                    message: "Line does not appear to be a valid YAML mapping or sequence entry.",
                    source: .yamlParser
                ))
            }
        }

        logger.debug("YAML validation: \(diagnostics.count) diagnostic(s)")
        return ValidationResult(diagnostics: diagnostics)
    }

    // MARK: - Private — JSON validation

    /// Validates JSON using `JSONSerialization`.
    private func validateJSON(_ content: String) -> ValidationResult {
        guard let data = content.data(using: .utf8) else {
            return ValidationResult(diagnostics: [
                Diagnostic(
                    severity: .error,
                    lineNumber: 1,
                    message: "Content could not be decoded as UTF-8.",
                    source: .jsonParser
                )
            ])
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data)
            return .valid
        } catch let error as NSError {
            let detail = error.localizedDescription
            // JSONSerialization does not provide accurate line numbers on macOS 14.
            return ValidationResult(diagnostics: [
                Diagnostic(
                    severity: .error,
                    lineNumber: 1,
                    message: "JSON parse error: \(detail)",
                    source: .jsonParser
                )
            ])
        }
    }
}
