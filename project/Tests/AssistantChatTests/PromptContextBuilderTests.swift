// PromptContextBuilderTests.swift — assistant_chat bounded context
// XCTest coverage: PromptContextBuilder Layer-2 structural tagging (ADR-0048).

import XCTest
@testable import AssistantChat

// MARK: - PromptContextBuilderTests

final class PromptContextBuilderTests: XCTestCase {
    // MARK: - Helpers

    private let builder = PromptContextBuilder()

    // MARK: - Test 1: clusterResource wraps in UNTRUSTED_DATA tags

    func test_build_clusterResource_wrapsInUntrustedDataTag() {
        let result = builder.build(
            sanitizedValue: "Hello world",
            source: .clusterResource(kind: "ConfigMap", name: "app-config")
        )

        XCTAssertTrue(result.contains("<UNTRUSTED_DATA"))
        XCTAssertTrue(result.contains("</UNTRUSTED_DATA>"))
        XCTAssertTrue(result.contains("Hello world"))
    }

    // MARK: - Test 2: clusterResource source attribute is correct

    func test_build_clusterResource_sourceAttributeContainsKindAndName() {
        let result = builder.build(
            sanitizedValue: "value",
            source: .clusterResource(kind: "Secret", name: "db-creds")
        )

        XCTAssertTrue(result.contains("source=\"Secret/db-creds\""))
    }

    // MARK: - Test 3: mcpToolResult wraps with mcp-tool prefix

    func test_build_mcpToolResult_sourceAttributeUsesMcpToolPrefix() {
        let result = builder.build(
            sanitizedValue: "{\"pods\":[]}",
            source: .mcpToolResult(toolName: "list-pods")
        )

        XCTAssertTrue(result.contains("source=\"mcp-tool/list-pods\""))
        XCTAssertTrue(result.contains("<UNTRUSTED_DATA"))
        XCTAssertTrue(result.contains("</UNTRUSTED_DATA>"))
    }

    // MARK: - Test 4: operatorMessage passes through verbatim

    func test_build_operatorMessage_noWrapping() {
        let input = "Show me the nginx deployment status."
        let result = builder.build(sanitizedValue: input, source: .operatorMessage)

        XCTAssertEqual(result, input)
        XCTAssertFalse(result.contains("<UNTRUSTED_DATA"))
    }

    // MARK: - Test 5: clusterResource tag structure has correct newlines

    func test_build_clusterResource_tagStructureHasNewlines() {
        let value = "key: value"
        let result = builder.build(
            sanitizedValue: value,
            source: .clusterResource(kind: "ConfigMap", name: "cfg")
        )

        // Expected format: <UNTRUSTED_DATA source="...">\nvalue\n</UNTRUSTED_DATA>
        XCTAssertTrue(result.contains("\n\(value)\n"))
    }

    // MARK: - Test 6: mcpToolResult tag structure has correct newlines

    func test_build_mcpToolResult_tagStructureHasNewlines() {
        let value = "replicas: 3"
        let result = builder.build(
            sanitizedValue: value,
            source: .mcpToolResult(toolName: "get-deployment")
        )

        XCTAssertTrue(result.contains("\n\(value)\n"))
    }

    // MARK: - Test 7: Empty value still produces valid wrapping

    func test_build_clusterResource_emptyValue_producesValidTag() {
        let result = builder.build(
            sanitizedValue: "",
            source: .clusterResource(kind: "ConfigMap", name: "empty-cfg")
        )

        XCTAssertTrue(result.hasPrefix("<UNTRUSTED_DATA"))
        XCTAssertTrue(result.hasSuffix("</UNTRUSTED_DATA>"))
    }

    // MARK: - Test 8: Newlines inside value are preserved

    func test_build_clusterResource_multilineValue_preservesNewlines() {
        let multiline = "line1\nline2\nline3"
        let result = builder.build(
            sanitizedValue: multiline,
            source: .clusterResource(kind: "Pod", name: "my-pod")
        )

        XCTAssertTrue(result.contains("line1\nline2\nline3"))
    }

    // MARK: - Test 9: Source attribute with special characters is not escaped

    func test_build_clusterResource_specialCharactersInName_includedVerbatim() {
        // Kubernetes names can include hyphens and dots.
        let result = builder.build(
            sanitizedValue: "v",
            source: .clusterResource(kind: "Deployment", name: "my-app.v2")
        )

        XCTAssertTrue(result.contains("Deployment/my-app.v2"))
    }

    // MARK: - Test 10: Two calls produce independent fragments

    func test_build_twoFragments_areIndependent() {
        let a = builder.build(
            sanitizedValue: "alpha",
            source: .clusterResource(kind: "ConfigMap", name: "a")
        )
        let b = builder.build(
            sanitizedValue: "beta",
            source: .mcpToolResult(toolName: "b")
        )

        XCTAssertFalse(a.contains("beta"))
        XCTAssertFalse(b.contains("alpha"))
    }
}
