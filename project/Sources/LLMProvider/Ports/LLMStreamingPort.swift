// Ports/LLMStreamingPort.swift — llm_provider bounded context
// DDD role: Port (primary — outbound to provider adapters)
// Narrative ref: domain/narrative.md §Tactical roles — LLMProviderPort

import Foundation
import Logging

// MARK: - LLMStreamingPort

/// Primary streaming completion port.
///
/// Declared in the domain core; implemented by `AnthropicAdapter`,
/// `OpenAIAdapter`, and `OpenAICompatibleAdapter` in infrastructure.
/// The domain core never imports provider SDKs.
///
/// Cancellation propagates from the consumer's `Task` to the underlying HTTP
/// request within 200 ms (per domain invariant in `narrative.md`).
public protocol LLMStreamingPort: Sendable {
    /// Opens a streaming completion against the provider identified by
    /// `request.profileId`.
    ///
    /// - Parameter request: Conversation history, tool registry, optional
    ///   sampling override, and selected profile identifier.
    /// - Returns: An `AsyncThrowingStream` of normalised events. The stream
    ///   MUST emit exactly one `.finish` event as its last element and at most
    ///   one `.usage` event.
    /// - Throws: `LLMStreamingError` on connection failure. Transport errors
    ///   after stream open are delivered as `.finish(.error)` events rather
    ///   than thrown.
    func reply(to request: AssistantRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error>
}

// MARK: - LLMStreamingError

/// Errors thrown by `LLMStreamingPort` implementations before the stream opens.
public enum LLMStreamingError: Error, Sendable {
    /// No profile with the requested `profileId` is registered.
    case profileNotFound(UUID)

    /// The key store returned no value for the profile's `keyAlias`.
    case keyNotFound(alias: String)

    /// The adapter could not establish a connection to the provider endpoint.
    case connectionFailed(detail: String)

    /// The port has not been registered in this process.
    case unimplemented
}

// MARK: - UnimplementedLLMStreamingPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedLLMStreamingPort: LLMStreamingPort {
    public init() {}

    public func reply(to request: AssistantRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LLMStreamingError.unimplemented)
        }
    }
}
