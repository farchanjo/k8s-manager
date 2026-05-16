// Domain/ProviderProfile.swift — llm_provider bounded context
// DDD role: AggregateRoot
// CUE source: docs/arch/contexts/llm_provider/schemas/provider_profile.cue

import Foundation
import SharedKernel

// MARK: - ProviderKind

/// The provider wire protocol this profile targets.
///
/// Mirrors the `kind` discriminant in `#ProviderProfile`.
public enum ProviderKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// Anthropic Messages API (`POST /v1/messages`).
    case anthropic

    /// OpenAI Chat Completions or Responses API.
    case openai

    /// OpenAI-compatible endpoint with a configurable `baseURL`.
    case openaiCompatible = "openai_compatible"
}

// MARK: - SamplingConfig

/// Sampling knobs forwarded verbatim to the provider adapter.
///
/// Mirrors `#SamplingConfig` from `provider_profile.cue`. Immutable value
/// object — produced by the operator settings surface.
public struct SamplingConfig: Hashable, Sendable, Codable {
    /// Temperature in `[0.0, 2.0]`.
    public let temperature: Double

    /// Nucleus sampling parameter in `(0.0, 1.0]`. Adapter-specific default
    /// when `nil`.
    public let topP: Double?

    /// Top-k sampling limit. Adapter-specific default when `nil`.
    public let topK: Int?

    /// Hard token cap for the completion. Must be in `(0, 128000]`.
    public let maxOutputTokens: Int

    /// Stop sequences injected into every request for this profile.
    public let stopSequences: [String]

    /// Provider-specific opt-ins (e.g., `"anthropic_prompt_caching": "ephemeral"`).
    public let providerHints: [String: String]

    public init(
        temperature: Double,
        topP: Double? = nil,
        topK: Int? = nil,
        maxOutputTokens: Int,
        stopSequences: [String] = [],
        providerHints: [String: String] = [:]
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxOutputTokens = maxOutputTokens
        self.stopSequences = stopSequences
        self.providerHints = providerHints
    }
}

// MARK: - ProviderProfile

/// Operator-configured LLM provider entry.
///
/// Mirrors `#ProviderProfile` from `provider_profile.cue`. The aggregate root
/// for the `llm_provider` context — persisted by `local_persistence`. The API
/// key is never stored inline; `keyAlias` is a Keychain reference resolved by
/// `LLMKeyStorePort` at request time.
public struct ProviderProfile: Hashable, Sendable, Codable {
    /// UUIDv7-shaped stable identifier. Never changes on rename.
    public let id: UUID

    /// Operator-chosen label. 1–80 characters.
    public let displayName: String

    /// Provider wire protocol.
    public let kind: ProviderKind

    /// Required for `openaiCompatible`; ignored (not stored) for other kinds.
    /// The adapter resolves the canonical URL at request time for
    /// `anthropic` and `openai`.
    public let baseURL: URL?

    /// Provider-side model identifier (e.g., `"claude-sonnet-4-6"`).
    public let modelId: String

    /// Keychain entry reference. NEVER the key value itself.
    public let keyAlias: String

    /// Default sampling parameters applied when the caller does not override.
    public let samplingDefaults: SamplingConfig

    /// RFC3339 creation timestamp.
    public let createdAtRFC3339: String

    /// RFC3339 last-modified timestamp.
    public let updatedAtRFC3339: String

    public init(
        id: UUID,
        displayName: String,
        kind: ProviderKind,
        baseURL: URL? = nil,
        modelId: String,
        keyAlias: String,
        samplingDefaults: SamplingConfig,
        createdAtRFC3339: String,
        updatedAtRFC3339: String
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.baseURL = baseURL
        self.modelId = modelId
        self.keyAlias = keyAlias
        self.samplingDefaults = samplingDefaults
        self.createdAtRFC3339 = createdAtRFC3339
        self.updatedAtRFC3339 = updatedAtRFC3339
    }
}
