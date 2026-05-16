// AnthropicStreamingAdapter.swift — infrastructure adapter
// Implements: LLMStreamingPort from LLMProvider
// Library: jamesrochabrun/SwiftAnthropic 2.2.2 (Tier B per ADR-0019)
// Concurrency: actor — Tier B @preconcurrency import boundary

@preconcurrency import SwiftAnthropic
import Foundation
import LLMProvider
import Logging

// MARK: - AnthropicStreamingAdapter

/// Streams completions from the Anthropic Messages API.
///
/// Implements `LLMStreamingPort` using `jamesrochabrun/SwiftAnthropic` 2.2.2.
/// Actor isolation satisfies the Tier B `@preconcurrency` boundary from ADR-0019.
public actor AnthropicStreamingAdapter: LLMStreamingPort {

    // MARK: Private state

    private let service: any AnthropicService
    private let model: String
    private let logger: Logger

    // MARK: Init

    /// Creates a streaming adapter backed by the Anthropic Messages API.
    ///
    /// - Parameters:
    ///   - apiKey: Anthropic secret key. Never logged or persisted.
    ///   - model: Provider-side model identifier (e.g. `"claude-sonnet-4-6"`).
    ///   - baseURL: Optional endpoint override. Defaults to `https://api.anthropic.com`.
    public init(apiKey: String, model: String, baseURL: URL? = nil) {
        let basePath = baseURL?.absoluteString ?? "https://api.anthropic.com"
        self.service = AnthropicServiceFactory.service(
            apiKey: apiKey,
            basePath: basePath,
            betaHeaders: nil
        )
        self.model = model
        self.logger = Logger(label: "anthropic-adapter")
    }

    // MARK: LLMStreamingPort

    /// Opens a streaming completion against the Anthropic Messages API.
    ///
    /// - Parameter request: Conversation history, tool registry, and sampling overrides.
    /// - Returns: A normalised event stream. Emits exactly one `.finish` as its last element.
    ///
    /// `nonisolated` satisfies the protocol requirement. The Task hops onto the actor
    /// to copy isolated state before any async work begins.
    public nonisolated func reply(
        to request: AssistantRequest
    ) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            // Capture self for actor-hop; do NOT access isolated properties here.
            let actor = self
            Task {
                // Hop into actor isolation to read immutable stored properties.
                let capturedService = await actor.isolatedService
                let capturedModel = await actor.isolatedModel
                do {
                    let parameter = try Self.buildParameter(request: request, model: capturedModel)
                    let upstream = try await capturedService.streamMessage(parameter)
                    var state = StreamState()
                    for try await chunk in upstream {
                        let events = Self.mapChunk(chunk, state: &state)
                        for event in events { continuation.yield(event) }
                    }
                    if !state.finishEmitted {
                        continuation.yield(.finish(FinishEvent(reason: .stop)))
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.finish(FinishEvent(reason: .error, detail: error.localizedDescription)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Actor-isolated accessors (for cross-isolation capture)

    fileprivate var isolatedService: any AnthropicService { service }
    fileprivate var isolatedModel: String { model }
}

// MARK: - Mutable stream state (value type, passed inout)

/// Tracks in-flight tool call buffers and whether a finish event was emitted.
struct StreamState {
    /// Maps content-block index → (callId, accumulated JSON).
    var toolBlocks: [Int: (callId: String, buffer: String)] = [:]
    var finishEmitted = false
}

// MARK: - Parameter construction

extension AnthropicStreamingAdapter {

    /// Builds a `MessageParameter` from the domain `AssistantRequest`.
    static func buildParameter(
        request: AssistantRequest,
        model: String
    ) throws -> MessageParameter {
        let (systemParts, conversationMessages) = splitMessages(request.messages)
        let system: MessageParameter.System? = buildSystem(from: systemParts)
        let messages = conversationMessages.compactMap(buildMessage)
        let tools: [MessageParameter.Tool]? = request.tools.isEmpty ? nil : request.tools.map(buildTool)
        let sampling = request.samplingOverride
        return MessageParameter(
            model: .other(model),
            messages: messages,
            maxTokens: sampling?.maxOutputTokens ?? 4096,
            system: system,
            stopSequences: (sampling?.stopSequences).flatMap { $0.isEmpty ? nil : $0 },
            stream: true,
            temperature: sampling?.temperature,
            topK: sampling?.topK,
            topP: sampling?.topP,
            tools: tools
        )
    }

    private static func splitMessages(
        _ messages: [AssistantMessage]
    ) -> ([AssistantMessage], [AssistantMessage]) {
        (
            messages.filter { $0.role == .system },
            messages.filter { $0.role != .system }
        )
    }

    private static func buildSystem(from systemMessages: [AssistantMessage]) -> MessageParameter.System? {
        let texts = systemMessages
            .flatMap(\.content)
            .compactMap { part -> String? in
                guard case .text(let t) = part else { return nil }
                return t.text
            }
        guard !texts.isEmpty else { return nil }
        return .text(texts.joined(separator: "\n"))
    }

    private static func buildMessage(_ message: AssistantMessage) -> MessageParameter.Message? {
        guard message.role == .user || message.role == .assistant else { return nil }
        let role: MessageParameter.Message.Role = message.role == .user ? .user : .assistant
        let objects = message.content.compactMap(buildContentObject)
        guard !objects.isEmpty else { return nil }
        return MessageParameter.Message(role: role, content: .list(objects))
    }

    private static func buildContentObject(
        _ part: MessagePart
    ) -> MessageParameter.Message.Content.ContentObject? {
        switch part {
        case .text(let t):
            if t.cacheControl == .ephemeral {
                return .cache(MessageParameter.Cache(
                    text: t.text,
                    cacheControl: MessageParameter.CacheControl(type: .ephemeral)
                ))
            }
            return .text(t.text)
        case .toolUse(let tu):
            let decoded = (try? JSONDecoder().decode(
                [String: MessageResponse.Content.DynamicContent].self,
                from: Data(tu.jsonArguments.utf8)
            )) ?? [:]
            return .toolUse(tu.callId, tu.name, decoded)
        case .toolResult(let tr):
            return .toolResult(tr.callId, tr.jsonResult, isError: tr.isError, cacheControl: nil)
        }
    }

    private static func buildTool(_ tool: ToolDefinition) -> MessageParameter.Tool {
        let schema = decodeJSONSchema(tool.inputJSONSchema)
        return .function(name: tool.name, description: tool.description, inputSchema: schema)
    }

    /// Decodes a raw UTF-8 JSON Schema string into a ``JSONSchema`` value.
    ///
    /// Returns `nil` on parse failure so callers degrade gracefully (Anthropic
    /// rejects requests whose tools have structurally invalid schemas).
    private static func decodeJSONSchema(_ raw: String) -> JSONSchema? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONSchema.self, from: data)
    }
}

// MARK: - Stream event mapping

extension AnthropicStreamingAdapter {

    /// Maps one `MessageStreamResponse` chunk to zero or more domain events.
    static func mapChunk(
        _ chunk: MessageStreamResponse,
        state: inout StreamState
    ) -> [AssistantStreamEvent] {
        switch chunk.streamEvent {
        case .contentBlockStart:
            return handleBlockStart(chunk, state: &state)
        case .contentBlockDelta:
            return handleBlockDelta(chunk, state: &state)
        case .contentBlockStop:
            return handleBlockStop(chunk, state: &state)
        case .messageDelta:
            return handleMessageDelta(chunk, state: &state)
        case .messageStart, .messageStop, .none:
            return []
        }
    }

    private static func handleBlockStart(
        _ chunk: MessageStreamResponse,
        state: inout StreamState
    ) -> [AssistantStreamEvent] {
        guard let block = chunk.contentBlock, let index = chunk.index else { return [] }
        if block.type == "tool_use", let id = block.id, let name = block.name {
            state.toolBlocks[index] = (callId: id, buffer: "")
            return [.toolUseStart(ToolUseStartEvent(callId: id, name: name))]
        }
        return []
    }

    private static func handleBlockDelta(
        _ chunk: MessageStreamResponse,
        state: inout StreamState
    ) -> [AssistantStreamEvent] {
        guard let delta = chunk.delta else { return [] }
        if delta.type == "text_delta", let text = delta.text {
            return [.delta(DeltaEvent(text: text))]
        }
        if delta.type == "input_json_delta",
           let partial = delta.partialJson,
           let index = chunk.index,
           state.toolBlocks[index] != nil {
            state.toolBlocks[index]!.buffer += partial
            let callId = state.toolBlocks[index]!.callId
            return [.toolUseDelta(ToolUseDeltaEvent(callId: callId, jsonChunk: partial))]
        }
        return []
    }

    private static func handleBlockStop(
        _ chunk: MessageStreamResponse,
        state: inout StreamState
    ) -> [AssistantStreamEvent] {
        guard let index = chunk.index,
              let block = state.toolBlocks.removeValue(forKey: index) else { return [] }
        return [.toolUseFinish(ToolUseFinishEvent(callId: block.callId, totalArguments: block.buffer))]
    }

    private static func handleMessageDelta(
        _ chunk: MessageStreamResponse,
        state: inout StreamState
    ) -> [AssistantStreamEvent] {
        var events: [AssistantStreamEvent] = []
        if let usage = chunk.usage {
            events.append(.usage(UsageEvent(
                promptTokens: usage.inputTokens ?? 0,
                completionTokens: usage.outputTokens,
                cachedPromptTokens: usage.cacheReadInputTokens
            )))
        }
        if let rawReason = chunk.delta?.stopReason {
            let reason = mapStopReason(rawReason)
            events.append(.finish(FinishEvent(reason: reason)))
            state.finishEmitted = true
        }
        return events
    }

    private static func mapStopReason(_ raw: String) -> FinishReason {
        switch raw {
        case "end_turn": return .stop
        case "max_tokens": return .maxTokens
        case "tool_use": return .toolUse
        default: return .stop
        }
    }
}
