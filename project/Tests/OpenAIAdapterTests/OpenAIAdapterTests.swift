// OpenAIAdapterTests.swift — OpenAIAdapterTests target
// Coverage: smoke construction, mapping helpers, event shape.

import XCTest
@testable import OpenAIAdapter
import LLMProvider

// MARK: - OpenAIStreamingAdapterConstructionTests

final class OpenAIStreamingAdapterConstructionTests: XCTestCase {

    func test_init_doesNotThrow() {
        // Verify the actor can be constructed without crashing.
        let adapter = OpenAIStreamingAdapter(
            apiKey: "sk-test-1234",
            model: "gpt-4o"
        )
        XCTAssertNotNil(adapter)
    }

    func test_reply_returns_stream() async {
        // Verify reply(to:) returns an AsyncThrowingStream without precondition failures.
        let adapter = OpenAIStreamingAdapter(apiKey: "sk-test", model: "gpt-4o")
        let request = AssistantRequest(
            messages: [AssistantMessage(
                role: .user,
                content: [.text(TextPart(text: "ping"))]
            )],
            profileId: UUID()
        )
        // Stream should be constructable; we do not drain it (no live key).
        let stream = await adapter.reply(to: request)
        XCTAssertNotNil(stream)
    }
}

// MARK: - OpenAIChatMapperMessageTests

final class OpenAIChatMapperMessageTests: XCTestCase {

    func test_systemMessage_mapsToSystem() {
        let msg = AssistantMessage(
            role: .system,
            content: [.text(TextPart(text: "You are a helpful assistant."))]
        )
        let result = OpenAIChatMapper.toChatMessages([msg])
        XCTAssertEqual(result.count, 1)
        guard case .system(let p) = result[0] else {
            return XCTFail("Expected .system param")
        }
        guard case .textContent(let text) = p.content else {
            return XCTFail("Expected .textContent")
        }
        XCTAssertEqual(text, "You are a helpful assistant.")
    }

    func test_userMessage_mapsToUser() {
        let msg = AssistantMessage(
            role: .user,
            content: [.text(TextPart(text: "Hello"))]
        )
        let result = OpenAIChatMapper.toChatMessages([msg])
        XCTAssertEqual(result.count, 1)
        guard case .user(let p) = result[0] else {
            return XCTFail("Expected .user param")
        }
        guard case .string(let text) = p.content else {
            return XCTFail("Expected .string content")
        }
        XCTAssertEqual(text, "Hello")
    }

    func test_toolResultMessage_mapsToTool() {
        let msg = AssistantMessage(
            role: .tool,
            content: [.toolResult(ToolResultPart(
                callId: "call_xyz",
                jsonResult: #"{"pods":[]}"#,
                isError: false
            ))]
        )
        let result = OpenAIChatMapper.toChatMessages([msg])
        XCTAssertEqual(result.count, 1)
        guard case .tool(let p) = result[0] else {
            return XCTFail("Expected .tool param")
        }
        XCTAssertEqual(p.toolCallId, "call_xyz")
    }

    func test_emptyMessages_producesEmptyArray() {
        XCTAssertTrue(OpenAIChatMapper.toChatMessages([]).isEmpty)
    }
}

// MARK: - OpenAIChatMapperToolTests

final class OpenAIChatMapperToolTests: XCTestCase {

    func test_toChatTools_mapsNameAndDescription() {
        let def = ToolDefinition(
            name: "list_pods",
            description: "Lists all pods in a namespace",
            inputJSONSchema: #"{"type":"object"}"#
        )
        let result = OpenAIChatMapper.toChatTools([def])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].function.name, "list_pods")
        XCTAssertEqual(result[0].function.description, "Lists all pods in a namespace")
    }

    func test_toChatTools_emptyInput_producesEmptyArray() {
        XCTAssertTrue(OpenAIChatMapper.toChatTools([]).isEmpty)
    }

    func test_toStop_nilInput_returnsNil() {
        XCTAssertNil(OpenAIChatMapper.toStop(nil))
    }

    func test_toStop_emptyArray_returnsNil() {
        XCTAssertNil(OpenAIChatMapper.toStop([]))
    }

    func test_toStop_singleSequence_returnsString() {
        let stop = OpenAIChatMapper.toStop(["</s>"])
        guard case .string(let s) = stop else {
            return XCTFail("Expected .string stop")
        }
        XCTAssertEqual(s, "</s>")
    }

    func test_toStop_multipleSequences_returnsStringList() {
        let stop = OpenAIChatMapper.toStop(["</s>", "<|end|>"])
        guard case .stringList(let list) = stop else {
            return XCTFail("Expected .stringList stop")
        }
        XCTAssertEqual(list.count, 2)
    }
}

// MARK: - ArrayNonEmptyOrNilTests

final class ArrayNonEmptyOrNilTests: XCTestCase {

    func test_emptyArray_returnsNil() {
        let arr: [Int] = []
        XCTAssertNil(arr.nonEmptyOrNil)
    }

    func test_nonEmptyArray_returnsSelf() {
        let arr = [1, 2, 3]
        XCTAssertEqual(arr.nonEmptyOrNil, arr)
    }
}
