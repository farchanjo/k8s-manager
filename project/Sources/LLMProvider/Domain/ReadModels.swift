// Domain/ReadModels.swift — llm_provider bounded context
// DDD role: Read models exposed to other bounded contexts
// Narrative ref: domain/narrative.md §Read models exposed to other contexts

import Foundation

// MARK: - ProviderListReadModel

/// Flat projection of all configured provider profiles.
///
/// Consumed by `app_shell` to render the settings surface. Contains no
/// credential material — `keyAlias` is omitted intentionally.
public struct ProviderListReadModel: Sendable {
    /// One row in the flat list.
    public struct Row: Identifiable, Sendable {
        public let id: UUID
        public let displayName: String
        public let kind: ProviderKind
        public let modelId: String
        /// RFC3339 timestamp of the last successful feature-detection probe,
        /// or `nil` when the profile has never been verified.
        public let lastVerifiedAtRFC3339: String?

        public init(
            id: UUID,
            displayName: String,
            kind: ProviderKind,
            modelId: String,
            lastVerifiedAtRFC3339: String? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.kind = kind
            self.modelId = modelId
            self.lastVerifiedAtRFC3339 = lastVerifiedAtRFC3339
        }
    }

    public let rows: [Row]

    public init(rows: [Row]) {
        self.rows = rows
    }
}

// MARK: - ProviderCapabilityReadModel

/// Feature-detection snapshot for one provider profile.
///
/// Consumed by `assistant_chat` to decide whether to advertise tools to the
/// model. Populated after a successful feature-detection probe.
public struct ProviderCapabilityReadModel: Sendable {
    /// Profile this capability snapshot belongs to.
    public let profileId: UUID

    /// `true` when the provider is known to support tool / function calling.
    public let supportsToolUse: Bool

    /// `true` when the provider supports prompt caching (e.g., Anthropic
    /// via `providerHints["anthropic_prompt_caching"]`).
    public let supportsPromptCaching: Bool

    /// `true` when the provider supports streaming responses.
    public let supportsStreaming: Bool

    /// RFC3339 timestamp of the feature-detection probe that produced this
    /// snapshot.
    public let detectedAtRFC3339: String

    public init(
        profileId: UUID,
        supportsToolUse: Bool,
        supportsPromptCaching: Bool,
        supportsStreaming: Bool,
        detectedAtRFC3339: String
    ) {
        self.profileId = profileId
        self.supportsToolUse = supportsToolUse
        self.supportsPromptCaching = supportsPromptCaching
        self.supportsStreaming = supportsStreaming
        self.detectedAtRFC3339 = detectedAtRFC3339
    }
}
