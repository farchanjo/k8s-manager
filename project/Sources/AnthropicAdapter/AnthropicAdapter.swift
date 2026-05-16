// AnthropicAdapter.swift — infrastructure adapter
// Implements: LLMStreamingPort via AnthropicStreamingAdapter
// Library: jamesrochabrun/SwiftAnthropic 2.2.2 (Tier B per ADR-0019)
// ADR ref: ADR-0008 (LLM provider abstraction)
@preconcurrency import SwiftAnthropic
import LLMProvider
import Foundation

/// Tier B import boundary — wrap upstream callbacks in actor-isolated state.
/// See ADR-0019 §"Tier classification" and ADR-0011 concurrency conventions.

/// Namespace marker for the AnthropicAdapter infrastructure target.
///
/// The real implementation lives in ``AnthropicStreamingAdapter`` which
/// conforms to ``LLMStreamingPort`` and streams Anthropic Messages API
/// responses as ``AssistantStreamEvent`` values.
public enum AnthropicAdapter: Sendable {
    public static let moduleVersion = "1.0.0"
}
