// OpenAICompatibleStreamingAdapter.swift — OpenAICompatibleAdapter target
// Implements: LLMStreamingPort for OpenAI-compatible endpoints.
// Compatible with Ollama, LM Studio, vLLM, and other OpenAI-compat servers.
// Library: MacPaw/OpenAI@0.4.9 (Tier B per ADR-0019)

@preconcurrency import OpenAI
import Foundation
import LLMProvider
import Logging

// MARK: - OpenAICompatibleStreamingAdapter

/// Streaming adapter for OpenAI-compatible endpoints (Ollama, LM Studio, vLLM).
///
/// Accepts a configurable `host`, `port`, `scheme`, and optional `apiKey`.
/// The same `MacPaw/OpenAI` client + mapping path as `OpenAIStreamingAdapter`
/// — only the `OpenAI.Configuration` differs (per ADR-0019 §Tier B reuse).
public actor OpenAICompatibleStreamingAdapter: LLMStreamingPort {

    // MARK: Private state

    private let model: String
    private let client: OpenAI
    private let logger: Logger

    // MARK: Init

    /// Creates an adapter targeting an OpenAI-compatible endpoint.
    ///
    /// - Parameters:
    ///   - apiKey:  Optional bearer token (`nil` = no `Authorization` header).
    ///   - host:    Remote host, e.g. `"localhost"` or `"ollama.corp.local"`.
    ///   - port:    Optional port override (`nil` uses scheme default).
    ///   - scheme:  URL scheme — `"http"` or `"https"`. Defaults to `"http"`.
    ///   - model:   Provider-side model identifier.
    ///   - logger:  Optional logger label.
    public init(
        apiKey: String? = nil,
        host: String,
        port: Int? = nil,
        scheme: String = "http",
        model: String,
        logger: Logger = Logger(label: "OpenAICompatibleStreamingAdapter")
    ) {
        let resolvedPort = port ?? (scheme == "https" ? 443 : 80)
        let config = OpenAI.Configuration(
            token: apiKey,
            host: host,
            port: resolvedPort,
            scheme: scheme
        )
        self.client = OpenAI(configuration: config)
        self.model = model
        self.logger = logger
    }

    // MARK: LLMStreamingPort

    /// Opens a streaming completion against the configured compatible endpoint.
    ///
    /// Transport errors after stream open are delivered as `.finish(.error)`.
    public nonisolated func reply(
        to request: AssistantRequest
    ) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
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
                        messages: OpenAICompatibleChatMapper.toChatMessages(messages),
                        model: Model(model),
                        maxCompletionTokens: sampling?.maxOutputTokens,
                        stop: OpenAICompatibleChatMapper.toStop(sampling?.stopSequences),
                        temperature: sampling?.temperature,
                        tools: OpenAICompatibleChatMapper.toChatTools(tools).nonEmptyOrNilCompat,
                        stream: true,
                        streamOptions: ChatQuery.StreamOptions(includeUsage: true)
                    )

                    var toolBuffers: [Int: OpenAICompatibleToolBuffer] = [:]
                    for try await chunk in client.chatsStream(query: query) {
                        let events = OpenAICompatibleChatMapper.toStreamEvents(
                            chunk: chunk,
                            toolBuffers: &toolBuffers
                        )
                        for event in events {
                            continuation.yield(event)
                        }
                    }
                    continuation.yield(.finish(FinishEvent(reason: .stop)))
                    continuation.finish()
                } catch {
                    logger.error("OpenAI-compatible stream error: \(error)")
                    continuation.yield(.finish(FinishEvent(reason: .error, detail: error.localizedDescription)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
