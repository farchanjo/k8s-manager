// OpenAIAdapter.swift — infrastructure adapter placeholder
// Implements: LLMProviderPort from LLMProvider
// Library: MacPaw/OpenAI@0.3+ (Tier B per ADR-0019)
// Status: skeleton; port implementations pending domain ports definition.
@preconcurrency import OpenAI
import LLMProvider
import Foundation

/// Tier B import boundary — wrap upstream callbacks in actor-isolated state.
/// See ADR-0019 §"Tier classification" and ADR-0011 concurrency conventions.

/// Namespace marker for the OpenAIAdapter adapter target.
///
/// Concrete actor types implementing the domain ports land under this enum
/// in subsequent rounds. This file exists so the target compiles cleanly
/// under Swift 6 strict concurrency with the imported infrastructure library.
public enum OpenAIAdapter: Sendable {
    public static let moduleVersion = "0.0.1-skeleton"
}
