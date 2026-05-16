// OpenAIChatMapper.swift — OpenAIAdapter target
// Module-internal mapping helpers: domain types → MacPaw OpenAI types.

@preconcurrency import OpenAI
import Foundation
import LLMProvider

// MARK: - OpenAIToolBuffer

/// Accumulates streamed tool-call fragments for one in-flight call.
struct OpenAIToolBuffer {
    var callId: String
    var name: String
    var argumentsAccumulator: String = ""
}

// MARK: - OpenAIChatMapper

/// Pure mapping functions — no state, no I/O.
enum OpenAIChatMapper {

    // MARK: Messages

    /// Converts domain `AssistantMessage` array to MacPaw `ChatCompletionMessageParam` array.
    static func toChatMessages(
        _ messages: [AssistantMessage]
    ) -> [ChatQuery.ChatCompletionMessageParam] {
        messages.compactMap { toChatMessage($0) }
    }

    private static func toChatMessage(
        _ message: AssistantMessage
    ) -> ChatQuery.ChatCompletionMessageParam? {
        switch message.role {
        case .system:
            let text = extractPlainText(message.content)
            return .system(.init(content: .textContent(text)))
        case .user:
            let text = extractPlainText(message.content)
            return .user(.init(content: .string(text)))
        case .assistant:
            return toAssistantParam(message.content)
        case .tool:
            return toToolParam(message.content)
        }
    }

    private static func extractPlainText(_ parts: [MessagePart]) -> String {
        parts.compactMap {
            if case .text(let t) = $0 { return t.text }
            return nil
        }.joined()
    }

    private static func toAssistantParam(
        _ parts: [MessagePart]
    ) -> ChatQuery.ChatCompletionMessageParam? {
        let text = extractPlainText(parts)
        let toolCalls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam] =
            parts.compactMap {
                guard case .toolUse(let tu) = $0 else { return nil }
                return .init(
                    id: tu.callId,
                    function: .init(arguments: tu.jsonArguments, name: tu.name)
                )
            }

        let content: ChatQuery.ChatCompletionMessageParam.TextOrRefusalContent? =
            text.isEmpty ? nil : .textContent(text)
        return .assistant(.init(content: content, toolCalls: toolCalls.nonEmptyOrNil))
    }

    private static func toToolParam(
        _ parts: [MessagePart]
    ) -> ChatQuery.ChatCompletionMessageParam? {
        guard let first = parts.first, case .toolResult(let tr) = first else { return nil }
        return .tool(.init(content: .textContent(tr.jsonResult), toolCallId: tr.callId))
    }

    // MARK: Tools

    /// Converts domain `ToolDefinition` array to MacPaw `ChatCompletionToolParam` array.
    static func toChatTools(
        _ tools: [ToolDefinition]
    ) -> [ChatQuery.ChatCompletionToolParam] {
        tools.map { def in
            .init(function: .init(
                name: def.name,
                description: def.description
            ))
        }
    }

    // MARK: Stop sequences

    /// Wraps a non-empty stop sequence list into a `Stop`; returns `nil` otherwise.
    static func toStop(_ sequences: [String]?) -> ChatQuery.Stop? {
        guard let seqs = sequences, !seqs.isEmpty else { return nil }
        return seqs.count == 1 ? .string(seqs[0]) : .stringList(seqs)
    }

    // MARK: Stream events

    /// Translates one `ChatStreamResult` chunk into zero or more domain events.
    static func toStreamEvents(
        chunk: ChatStreamResult,
        toolBuffers: inout [Int: OpenAIToolBuffer]
    ) -> [AssistantStreamEvent] {
        var events: [AssistantStreamEvent] = []

        if let usage = chunk.usage {
            events.append(.usage(UsageEvent(
                promptTokens: usage.promptTokens,
                completionTokens: usage.completionTokens
            )))
        }

        for choice in chunk.choices {
            let delta = choice.delta

            if let text = delta.content, !text.isEmpty {
                events.append(.delta(DeltaEvent(text: text)))
            }

            if let toolCalls = delta.toolCalls {
                for tc in toolCalls {
                    events += processToolCallDelta(tc, into: &toolBuffers)
                }
            }

            if let reason = choice.finishReason {
                let finishEvents = flushToolBuffers(&toolBuffers)
                events += finishEvents
                events.append(.finish(FinishEvent(reason: mapFinishReason(reason))))
            }
        }

        return events
    }

    // MARK: Private helpers

    private static func processToolCallDelta(
        _ tc: ChatStreamResult.Choice.ChoiceDelta.ChoiceDeltaToolCall,
        into buffers: inout [Int: OpenAIToolBuffer]
    ) -> [AssistantStreamEvent] {
        var events: [AssistantStreamEvent] = []
        let idx = tc.index

        if buffers[idx] == nil, let id = tc.id, let name = tc.function?.name {
            buffers[idx] = OpenAIToolBuffer(callId: id, name: name)
            events.append(.toolUseStart(ToolUseStartEvent(callId: id, name: name)))
        }

        if let args = tc.function?.arguments, !args.isEmpty, buffers[idx] != nil {
            buffers[idx]!.argumentsAccumulator += args
            events.append(.toolUseDelta(ToolUseDeltaEvent(
                callId: buffers[idx]!.callId,
                jsonChunk: args
            )))
        }

        return events
    }

    private static func flushToolBuffers(
        _ buffers: inout [Int: OpenAIToolBuffer]
    ) -> [AssistantStreamEvent] {
        buffers.sorted { $0.key < $1.key }.map { _, buf in
            AssistantStreamEvent.toolUseFinish(ToolUseFinishEvent(
                callId: buf.callId,
                totalArguments: buf.argumentsAccumulator
            ))
        }
    }

    private static func mapFinishReason(
        _ reason: ChatStreamResult.Choice.FinishReason
    ) -> FinishReason {
        switch reason {
        case .stop: return .stop
        case .length: return .maxTokens
        case .toolCalls: return .toolUse
        case .contentFilter: return .error
        case .functionCall: return .toolUse
        case .error: return .error
        }
    }
}

// MARK: - Array convenience

extension Array {
    /// Returns `nil` when the array is empty; otherwise returns `self`.
    var nonEmptyOrNil: Self? { isEmpty ? nil : self }
}
