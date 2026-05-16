// RealtimeValidatorServiceTests.swift — ResourceBrowserTests target
// Coverage: RealtimeValidatorService — YAML/JSON syntax validation.
// ADR refs: ADR-0030 (integrated editor, real-time syntactic validation)

import XCTest
@testable import ResourceBrowser
import SharedKernel

// MARK: - Tests

final class RealtimeValidatorServiceYAMLTests: XCTestCase {

    private let validator = RealtimeValidatorService()
    private let podGVK = GroupVersionKind.core("Pod")

    func test_validate_validYAML_returnsEmptyDiagnostics() async {
        let yaml = """
        apiVersion: v1
        kind: Pod
        metadata:
          name: my-pod
          namespace: default
        """
        let result = await validator.validate(yaml, gvk: podGVK)
        XCTAssertTrue(result.isValid, "Valid YAML should produce no error diagnostics")
    }

    func test_validate_yamlWithTab_returnsErrorDiagnostic() async {
        let yaml = "\tapiVersion: v1"
        let result = await validator.validate(yaml, gvk: podGVK)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.diagnostics.contains { $0.message.contains("Tab") })
    }

    func test_validate_emptyContent_returnsValid() async {
        let result = await validator.validate("", gvk: podGVK)
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.diagnostics.isEmpty)
    }

    func test_validate_whiteSpaceOnly_returnsValid() async {
        let result = await validator.validate("   \n  ", gvk: podGVK)
        XCTAssertTrue(result.isValid)
    }
}

final class RealtimeValidatorServiceJSONTests: XCTestCase {

    private let validator = RealtimeValidatorService()
    private let gvk = GroupVersionKind.core("ConfigMap")

    func test_validate_validJSON_returnsValid() async {
        let json = #"{"apiVersion":"v1","kind":"ConfigMap","metadata":{"name":"cfg"}}"#
        let result = await validator.validate(json, gvk: gvk)
        XCTAssertTrue(result.isValid)
    }

    func test_validate_invalidJSON_returnsErrorDiagnostic() async {
        let malformed = #"{"apiVersion": "v1", "kind": "ConfigMap""#  // missing closing brace
        let result = await validator.validate(malformed, gvk: gvk)
        XCTAssertFalse(result.isValid)
        let sources = result.diagnostics.map(\.source)
        XCTAssertTrue(sources.contains(.jsonParser))
    }

    func test_validate_jsonArray_returnsValid() async {
        let json = "[1, 2, 3]"
        let result = await validator.validate(json, gvk: gvk)
        XCTAssertTrue(result.isValid)
    }
}

final class RealtimeValidatorServiceSeverityTests: XCTestCase {

    private let validator = RealtimeValidatorService()

    func test_validResult_isValid() {
        let result = ValidationResult.valid
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.diagnostics.isEmpty)
    }

    func test_resultWithErrorDiagnostic_isNotValid() {
        let diag = Diagnostic(
            severity: .error,
            lineNumber: 1,
            message: "Parse error",
            source: .yamlParser
        )
        let result = ValidationResult(diagnostics: [diag])
        XCTAssertFalse(result.isValid)
    }

    func test_resultWithWarningOnly_isStillValid() {
        let diag = Diagnostic(
            severity: .warning,
            lineNumber: 5,
            message: "Suspicious line",
            source: .yamlParser
        )
        let result = ValidationResult(diagnostics: [diag])
        XCTAssertTrue(result.isValid, "Warning-only results should still be considered valid")
    }
}
