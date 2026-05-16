// AnthropicAdapterTests.swift — unit tests for AnthropicStreamingAdapter
// Coverage: construction smoke + parameter-builder + stream-mapper helpers.
// No real API key required — all tests operate on pure domain types.

@preconcurrency import SwiftAnthropic
import XCTest
@testable import AnthropicAdapter
import LLMProvider
import Foundation

final class AnthropicAdapterTests: XCTestCase {

    // MARK: Construction smoke

    func testInit_withFakeKeyAndDefaultURL_doesNotThrow() {
        // Actor inits are synchronous — just verify no crash.
        let adapter = AnthropicStreamingAdapter(
            apiKey: "sk-ant-fake-key",
            model: "claude-sonnet-4-6"
        )
        XCTAssertNotNil(adapter)
    }

    func testInit_withCustomBaseURL_doesNotThrow() {
        let url = URL(string: "https://test.example.com")!
        let adapter = AnthropicStreamingAdapter(
            apiKey: "sk-ant-fake-key",
            model: "claude-haiku-4-5",
            baseURL: url
        )
        XCTAssertNotNil(adapter)
    }

    // MARK: reply returns a stream (does not throw synchronously)

    func testReply_returnsNonNilStream() {
        let adapter = AnthropicStreamingAdapter(
            apiKey: "sk-ant-fake-key",
            model: "claude-sonnet-4-6"
        )
        let request = AssistantRequest(
            messages: [
                AssistantMessage(role: .user, content: [.text(TextPart(text: "Hello"))])
            ],
            profileId: UUID()
        )
        // reply(to:) is nonisolated — we can call it without await.
        let stream = adapter.reply(to: request)
        XCTAssertNotNil(stream)
    }

    // MARK: buildParameter helpers

    func testBuildParameter_systemMessageBecomesSystem() throws {
        let request = AssistantRequest(
            messages: [
                AssistantMessage(role: .system, content: [.text(TextPart(text: "Be helpful."))]),
                AssistantMessage(role: .user, content: [.text(TextPart(text: "Hi"))]),
            ],
            profileId: UUID()
        )
        let param = try AnthropicStreamingAdapter.buildParameter(
            request: request,
            model: "claude-sonnet-4-6"
        )
        // System text should be populated; conversation should contain 1 user message.
        XCTAssertNotNil(param.system)
        XCTAssertEqual(param.messages.count, 1)
    }

    func testBuildParameter_emptyTools_messagesOnly() throws {
        // Verify that an empty tool list does not break parameter construction.
        let request = AssistantRequest(
            messages: [
                AssistantMessage(role: .user, content: [.text(TextPart(text: "hi"))]),
            ],
            profileId: UUID()
        )
        let param = try AnthropicStreamingAdapter.buildParameter(
            request: request,
            model: "claude-sonnet-4-6"
        )
        // Verify messages still encoded correctly even when tools are absent.
        XCTAssertEqual(param.messages.count, 1)
    }

    func testBuildParameter_withTools_messagesContainUserTurn() throws {
        let tool = ToolDefinition(
            name: "list_pods",
            description: "List Kubernetes pods",
            inputJSONSchema: #"{"type":"object","properties":{}}"#
        )
        let request = AssistantRequest(
            messages: [
                AssistantMessage(role: .user, content: [.text(TextPart(text: "go"))]),
            ],
            tools: [tool],
            profileId: UUID()
        )
        let param = try AnthropicStreamingAdapter.buildParameter(
            request: request,
            model: "claude-sonnet-4-6"
        )
        // tools field is internal to SwiftAnthropic; verify the message was encoded.
        XCTAssertEqual(param.messages.count, 1)
    }

    func testBuildParameter_withValidJSONSchema_toolSchemaDecoded() throws {
        // Verifies that a well-formed JSON Schema string is decoded and forwarded
        // to the SwiftAnthropic tool parameter by round-tripping through JSONEncoder.
        let jsonSchema = #"{"type":"object","properties":{"namespace":{"type":"string"}}}"#
        let tool = ToolDefinition(
            name: "list_pods",
            description: "List pods in namespace",
            inputJSONSchema: jsonSchema
        )
        let request = AssistantRequest(
            messages: [AssistantMessage(role: .user, content: [.text(TextPart(text: "hi"))])],
            tools: [tool],
            profileId: UUID()
        )
        let param = try AnthropicStreamingAdapter.buildParameter(request: request, model: "claude-sonnet-4-6")
        // Encode and inspect via JSON to verify the input_schema was forwarded.
        let encoded = try JSONEncoder().encode(param)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(json.contains("input_schema"), "Encoded parameter must contain input_schema key")
        XCTAssertTrue(json.contains("list_pods"), "Encoded parameter must contain tool name")
        XCTAssertEqual(param.messages.count, 1)
    }

    func testBuildParameter_withMalformedJSONSchema_doesNotThrow() throws {
        // A tool with an unparseable schema degrades gracefully (schema becomes nil)
        // rather than throwing and aborting the entire request.
        let tool = ToolDefinition(
            name: "bad_tool",
            description: "Tool with malformed schema",
            inputJSONSchema: "NOT_VALID_JSON"
        )
        let request = AssistantRequest(
            messages: [AssistantMessage(role: .user, content: [.text(TextPart(text: "hi"))])],
            tools: [tool],
            profileId: UUID()
        )
        XCTAssertNoThrow(
            try AnthropicStreamingAdapter.buildParameter(request: request, model: "claude-sonnet-4-6")
        )
    }

    func testBuildParameter_samplingOverride_propagatesMaxTokens() throws {
        let sampling = SamplingConfig(
            temperature: 0.7,
            maxOutputTokens: 1024
        )
        let request = AssistantRequest(
            messages: [
                AssistantMessage(role: .user, content: [.text(TextPart(text: "ping"))]),
            ],
            samplingOverride: sampling,
            profileId: UUID()
        )
        let param = try AnthropicStreamingAdapter.buildParameter(
            request: request,
            model: "claude-sonnet-4-6"
        )
        XCTAssertEqual(param.maxTokens, 1024)
        XCTAssertEqual(param.temperature ?? 0, 0.7, accuracy: 0.001)
    }

    func testBuildParameter_toolResultMessage_isSkipped() throws {
        // tool-role messages are filtered out (Anthropic uses user/assistant turns only).
        let request = AssistantRequest(
            messages: [
                AssistantMessage(role: .user, content: [.text(TextPart(text: "call"))]),
                AssistantMessage(
                    role: .tool,
                    content: [.toolResult(ToolResultPart(callId: "x", jsonResult: "{}", isError: false))]
                ),
            ],
            profileId: UUID()
        )
        let param = try AnthropicStreamingAdapter.buildParameter(
            request: request,
            model: "claude-sonnet-4-6"
        )
        // tool-role message is silently skipped — only user message remains.
        XCTAssertEqual(param.messages.count, 1)
    }

    // MARK: mapChunk helpers — text delta

    func testMapChunk_textDelta_yieldsDeltaEvent() {
        let chunk = makeChunk(
            type: "content_block_delta",
            delta: makeDelta(type: "text_delta", text: "hello")
        )
        var state = StreamState()
        let events = AnthropicStreamingAdapter.mapChunk(chunk, state: &state)
        XCTAssertEqual(events.count, 1)
        if case .delta(let d) = events[0] {
            XCTAssertEqual(d.text, "hello")
        } else {
            XCTFail("Expected .delta event")
        }
    }

    func testMapChunk_messageStop_yieldsNoEvents() {
        let chunk = makeChunk(type: "message_stop")
        var state = StreamState()
        let events = AnthropicStreamingAdapter.mapChunk(chunk, state: &state)
        XCTAssertTrue(events.isEmpty)
    }

    func testMapChunk_toolUseStart_yieldsToolUseStartEvent() {
        let chunk = makeChunk(
            type: "content_block_start",
            index: 0,
            contentBlock: makeContentBlock(type: "tool_use", id: "call-1", name: "get_pods")
        )
        var state = StreamState()
        let events = AnthropicStreamingAdapter.mapChunk(chunk, state: &state)
        XCTAssertEqual(events.count, 1)
        if case .toolUseStart(let e) = events[0] {
            XCTAssertEqual(e.callId, "call-1")
            XCTAssertEqual(e.name, "get_pods")
        } else {
            XCTFail("Expected .toolUseStart")
        }
    }

    func testMapChunk_toolStop_yieldsToolUseFinishEvent() {
        var state = StreamState()
        state.toolBlocks[0] = (callId: "call-1", buffer: #"{"ns":"default"}"#)
        let chunk = makeChunk(type: "content_block_stop", index: 0)
        let events = AnthropicStreamingAdapter.mapChunk(chunk, state: &state)
        XCTAssertEqual(events.count, 1)
        if case .toolUseFinish(let e) = events[0] {
            XCTAssertEqual(e.callId, "call-1")
            XCTAssertEqual(e.totalArguments, #"{"ns":"default"}"#)
        } else {
            XCTFail("Expected .toolUseFinish")
        }
        XCTAssertTrue(state.toolBlocks.isEmpty, "Buffer should be cleared after stop")
    }

    func testMapChunk_toolUseDelta_accumulatesBuffer() {
        var state = StreamState()
        state.toolBlocks[0] = (callId: "call-2", buffer: "")

        let chunk = makeChunk(
            type: "content_block_delta",
            index: 0,
            delta: makeDelta(type: "input_json_delta", partialJson: #"{"key":"#)
        )
        let events = AnthropicStreamingAdapter.mapChunk(chunk, state: &state)
        XCTAssertEqual(events.count, 1)
        if case .toolUseDelta(let d) = events[0] {
            XCTAssertEqual(d.callId, "call-2")
            XCTAssertEqual(d.jsonChunk, #"{"key":"#)
        } else {
            XCTFail("Expected .toolUseDelta")
        }
        XCTAssertEqual(state.toolBlocks[0]?.buffer, #"{"key":"#)
    }

    func testMapChunk_fullToolUseLoop_startDeltaFinish() {
        // Full tool-use relay: start → delta × 2 → finish
        var state = StreamState()
        let startChunk = makeChunk(
            type: "content_block_start",
            index: 0,
            contentBlock: makeContentBlock(type: "tool_use", id: "call-3", name: "exec_cmd")
        )
        let delta1 = makeChunk(
            type: "content_block_delta",
            index: 0,
            delta: makeDelta(type: "input_json_delta", partialJson: #"{"cmd":"#)
        )
        let delta2 = makeChunk(
            type: "content_block_delta",
            index: 0,
            delta: makeDelta(type: "input_json_delta", partialJson: #""ls"}"#)
        )
        let stopChunk = makeChunk(type: "content_block_stop", index: 0)

        let e0 = AnthropicStreamingAdapter.mapChunk(startChunk, state: &state)
        let e1 = AnthropicStreamingAdapter.mapChunk(delta1, state: &state)
        let e2 = AnthropicStreamingAdapter.mapChunk(delta2, state: &state)
        let e3 = AnthropicStreamingAdapter.mapChunk(stopChunk, state: &state)

        guard case .toolUseStart(let s) = e0[0] else { return XCTFail("Expected toolUseStart") }
        XCTAssertEqual(s.callId, "call-3")
        XCTAssertEqual(s.name, "exec_cmd")

        guard case .toolUseDelta(let d1) = e1[0] else { return XCTFail("Expected toolUseDelta #1") }
        XCTAssertEqual(d1.jsonChunk, #"{"cmd":"#)

        guard case .toolUseDelta(let d2) = e2[0] else { return XCTFail("Expected toolUseDelta #2") }
        XCTAssertEqual(d2.jsonChunk, #""ls"}"#)

        guard case .toolUseFinish(let f) = e3[0] else { return XCTFail("Expected toolUseFinish") }
        XCTAssertEqual(f.totalArguments, #"{"cmd":"ls"}"#)
        XCTAssertTrue(state.toolBlocks.isEmpty)
    }

    // MARK: Error-path: stream from unconnected adapter errors downstream

    func testReply_networkError_emitsFinishErrorThenThrows() async {
        let adapter = AnthropicStreamingAdapter(
            apiKey: "sk-ant-obviously-invalid",
            model: "claude-sonnet-4-6",
            baseURL: URL(string: "https://0.0.0.0:1")!
        )
        let request = AssistantRequest(
            messages: [
                AssistantMessage(role: .user, content: [.text(TextPart(text: "hello"))]),
            ],
            profileId: UUID()
        )
        let stream = adapter.reply(to: request)
        var receivedError = false
        do {
            for try await event in stream {
                if case .finish(let f) = event, f.reason == .error {
                    receivedError = true
                }
            }
        } catch {
            receivedError = true
        }
        XCTAssertTrue(receivedError, "Expected error finish event or thrown error")
    }
}

// MARK: - MessageStreamResponse factories (test helpers)

// `MessageStreamResponse` is Decodable-only with no memberwise init.
// We construct fixtures by round-tripping through JSON.

private func makeChunk(
    type: String,
    index: Int? = nil,
    delta: [String: Any]? = nil,
    contentBlock: [String: Any]? = nil,
    usage: [String: Any]? = nil
) -> MessageStreamResponse {
    var dict: [String: Any] = ["type": type]
    if let i = index { dict["index"] = i }
    if let d = delta { dict["delta"] = d }
    if let cb = contentBlock { dict["content_block"] = cb }
    if let u = usage { dict["usage"] = u }
    let data = try! JSONSerialization.data(withJSONObject: dict)
    // SwiftAnthropic's DefaultAnthropicService uses convertFromSnakeCase — mirror it here.
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(MessageStreamResponse.self, from: data)
}

private func makeDelta(type: String, text: String? = nil, partialJson: String? = nil) -> [String: Any] {
    var d: [String: Any] = ["type": type]
    if let t = text { d["text"] = t }
    if let p = partialJson { d["partial_json"] = p }
    return d
}

private func makeContentBlock(
    type: String,
    id: String? = nil,
    name: String? = nil
) -> [String: Any] {
    var d: [String: Any] = ["type": type]
    if let i = id { d["id"] = i }
    if let n = name { d["name"] = n }
    return d
}
