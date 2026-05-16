// OpenAIStreamingAdapter.swift — OpenAIAdapter target
// Implements: LLMStreamingPort for OpenAI production endpoint.
// Library: MacPaw/OpenAI@0.4.9 (Tier B per ADR-0019)

@preconcurrency import OpenAI
import Foundation
import LLMProvider
import Logging

// MARK: - OpenAIStreamingAdapter

/// Streaming adapter for the OpenAI production Chat Completions API.
///
/// Uses `MacPaw/OpenAI` `OpenAI.chatsStream(query:)` under the hood.
/// All upstream callbacks are confined to actor-isolated state per ADR-0011.
/// Init is injected — no globals, no singletons.
public actor OpenAIStreamingAdapter: LLMStreamingPort {

    // MARK: Private state

    private let model: String
    private let client: OpenAI
    private let logger: Logger

    // MARK: Init

    /// Creates an adapter targeting the production OpenAI endpoint.
    ///
    /// - Parameters:
    ///   - apiKey: Bearer token.  Must not be empty.
    ///   - model:  Provider-side model identifier, e.g. `"gpt-4o"`.
    ///   - logger: Optional logger; defaults to `"OpenAIStreamingAdapter"` label.
    public init(
        apiKey: String,
        model: String,
        logger: Logger = Logger(label: "OpenAIStreamingAdapter")
    ) {
        let config = OpenAI.Configuration(
            token: apiKey,
            host: "api.openai.com",
            port: 443,
            scheme: "https"
        )
        self.client = OpenAI(configuration: config)
        self.model = model
        self.logger = logger
    }

    // MARK: LLMStreamingPort

    /// Opens a streaming completion. Translates each `ChatStreamResult` chunk
    /// into the normalised `AssistantStreamEvent` union.
    ///
    /// Transport errors after stream open are delivered as `.finish(.error)`.
    public nonisolated func reply(
        to request: AssistantRequest
    ) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        // Capture isolated state as local let before leaving actor context.
        let model = self.model
        let client = self.client
        let logger = self.logger
        let sampling = request.samplingOverride
        let messages = request.messages
        let tools = request.tools

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let query = ChatQuery(
                        messages: OpenAIChatMapper.toChatMessages(messages),
                        model: Model(model),
                        maxCompletionTokens: sampling?.maxOutputTokens,
                        stop: OpenAIChatMapper.toStop(sampling?.stopSequences),
                        temperature: sampling?.temperature,
                        tools: OpenAIChatMapper.toChatTools(tools).nonEmptyOrNil,
                        stream: true,
                        streamOptions: ChatQuery.StreamOptions(includeUsage: true)
                    )

                    var toolBuffers: [Int: OpenAIToolBuffer] = [:]
                    for try await chunk in client.chatsStream(query: query) {
                        let events = OpenAIChatMapper.toStreamEvents(
                            chunk: chunk,
                            toolBuffers: &toolBuffers
                        )
                        for event in events {
                            continuation.yield(event)
                        }
                    }
                    // Emit finish if not already emitted by a finishReason chunk.
                    continuation.yield(.finish(FinishEvent(reason: .stop)))
                    continuation.finish()
                } catch {
                    logger.error("OpenAI stream error: \(error)")
                    continuation.yield(.finish(FinishEvent(reason: .error, detail: error.localizedDescription)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
