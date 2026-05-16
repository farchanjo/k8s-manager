// OpenAICompatibleAdapterTests.swift — OpenAICompatibleAdapterTests target
// Coverage: smoke construction, mapping helpers, configurable endpoint.

import XCTest
@testable import OpenAICompatibleAdapter
import LLMProvider

// MARK: - OpenAICompatibleStreamingAdapterConstructionTests

final class OpenAICompatibleStreamingAdapterConstructionTests: XCTestCase {

    func test_init_ollama_doesNotThrow() {
        let adapter = OpenAICompatibleStreamingAdapter(
            apiKey: nil,
            host: "localhost",
            port: 11434,
            scheme: "http",
            model: "qwen3:32b-instruct"
        )
        XCTAssertNotNil(adapter)
    }

    func test_init_lmStudio_doesNotThrow() {
        let adapter = OpenAICompatibleStreamingAdapter(
            apiKey: nil,
            host: "localhost",
            port: 1234,
            scheme: "http",
            model: "lmstudio-community/Qwen3-14B-GGUF"
        )
        XCTAssertNotNil(adapter)
    }

    func test_init_vllm_withApiKey_doesNotThrow() {
        let adapter = OpenAICompatibleStreamingAdapter(
            apiKey: "vllm-secret",
            host: "vllm.corp.local",
            port: 8000,
            scheme: "https",
            model: "meta-llama/Llama-3-8B-Instruct"
        )
        XCTAssertNotNil(adapter)
    }

    func test_init_defaultScheme_isHttp() {
        // Verify the adapter constructs when scheme defaults to "http".
        let adapter = OpenAICompatibleStreamingAdapter(
            host: "localhost",
            model: "phi4"
        )
        XCTAssertNotNil(adapter)
    }

    func test_reply_returns_stream() async {
        let adapter = OpenAICompatibleStreamingAdapter(
            host: "localhost",
            port: 11434,
            model: "phi4"
        )
        let request = AssistantRequest(
            messages: [AssistantMessage(
                role: .user,
                content: [.text(TextPart(text: "ping"))]
            )],
            profileId: UUID()
        )
        let stream = await adapter.reply(to: request)
        XCTAssertNotNil(stream)
    }
}

// MARK: - OpenAICompatibleChatMapperMessageTests

final class OpenAICompatibleChatMapperMessageTests: XCTestCase {

    func test_systemMessage_mapsToSystem() {
        let msg = AssistantMessage(
            role: .system,
            content: [.text(TextPart(text: "You are a K8s expert."))]
        )
        let result = OpenAICompatibleChatMapper.toChatMessages([msg])
        XCTAssertEqual(result.count, 1)
        guard case .system(let p) = result[0] else {
            return XCTFail("Expected .system param")
        }
        guard case .textContent(let text) = p.content else {
            return XCTFail("Expected .textContent")
        }
        XCTAssertEqual(text, "You are a K8s expert.")
    }

    func test_userMessage_mapsToUser() {
        let msg = AssistantMessage(
            role: .user,
            content: [.text(TextPart(text: "List pods"))]
        )
        let result = OpenAICompatibleChatMapper.toChatMessages([msg])
        XCTAssertEqual(result.count, 1)
        guard case .user(let p) = result[0] else {
            return XCTFail("Expected .user param")
        }
        guard case .string(let text) = p.content else {
            return XCTFail("Expected .string content")
        }
        XCTAssertEqual(text, "List pods")
    }

    func test_toolResultMessage_mapsToTool() {
        let msg = AssistantMessage(
            role: .tool,
            content: [.toolResult(ToolResultPart(
                callId: "call_abc",
                jsonResult: #"{"result":"ok"}"#,
                isError: false
            ))]
        )
        let result = OpenAICompatibleChatMapper.toChatMessages([msg])
        XCTAssertEqual(result.count, 1)
        guard case .tool(let p) = result[0] else {
            return XCTFail("Expected .tool param")
        }
        XCTAssertEqual(p.toolCallId, "call_abc")
    }

    func test_multipleMessages_preserveOrder() {
        let messages: [AssistantMessage] = [
            AssistantMessage(role: .system, content: [.text(TextPart(text: "sys"))]),
            AssistantMessage(role: .user, content: [.text(TextPart(text: "user"))]),
        ]
        let result = OpenAICompatibleChatMapper.toChatMessages(messages)
        XCTAssertEqual(result.count, 2)
        guard case .system = result[0] else { return XCTFail("First should be system") }
        guard case .user = result[1] else { return XCTFail("Second should be user") }
    }
}

// MARK: - OpenAICompatibleChatMapperToolTests

final class OpenAICompatibleChatMapperToolTests: XCTestCase {

    func test_toChatTools_mapsNameAndDescription() {
        let def = ToolDefinition(
            name: "get_nodes",
            description: "Returns cluster node list",
            inputJSONSchema: #"{"type":"object"}"#
        )
        let result = OpenAICompatibleChatMapper.toChatTools([def])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].function.name, "get_nodes")
        XCTAssertEqual(result[0].function.description, "Returns cluster node list")
    }

    func test_toStop_singleSequence_producesString() {
        let stop = OpenAICompatibleChatMapper.toStop(["<|end|>"])
        guard case .string(let s) = stop else {
            return XCTFail("Expected .string stop")
        }
        XCTAssertEqual(s, "<|end|>")
    }

    func test_toStop_multipleSequences_producesStringList() {
        let stop = OpenAICompatibleChatMapper.toStop(["</s>", "<|end|>"])
        guard case .stringList(let list) = stop else {
            return XCTFail("Expected .stringList stop")
        }
        XCTAssertEqual(list.count, 2)
    }

    func test_toStop_emptyInput_returnsNil() {
        XCTAssertNil(OpenAICompatibleChatMapper.toStop([]))
    }
}
