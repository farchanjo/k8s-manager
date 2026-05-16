// Ports/ProviderRepositoryPort.swift — local_persistence bounded context
// DDD role: Port (secondary — outbound to persistence infrastructure)
// Consumed by: llm_provider bounded context
// Narrative ref: domain/narrative.md §Tactical roles
// DBML ref: storage.dbml §provider_profiles

import Foundation
import SharedKernel

// MARK: - ProviderKind

/// LLM provider discriminant matching the `kind` column constraint.
public enum ProviderKind: String, Hashable, Sendable, Codable {
    case anthropic          = "anthropic"
    case openAI             = "openai"
    case openAICompatible   = "openai-compatible"
}

// MARK: - ProviderProfile

/// Read-model for an LLM provider profile row.
///
/// The API key is **not** present here — it is held exclusively in the macOS
/// Keychain entry identified by ``keyAlias`` (ADR-0010).
public struct ProviderProfile: Hashable, Sendable, Codable {
    public let id: UUID
    public let kind: ProviderKind
    public let displayName: String
    public let endpointURL: String
    public let model: String
    public let temperature: Double?
    /// Keychain account slug under `service="com.archanjo.K8sManager.llm"`.
    /// Never the API key value itself.
    public let keyAlias: String
    /// `true` for Ollama / LM Studio profiles that require no network key.
    public let localOnly: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        kind: ProviderKind,
        displayName: String,
        endpointURL: String,
        model: String,
        temperature: Double? = nil,
        keyAlias: String,
        localOnly: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.endpointURL = endpointURL
        self.model = model
        self.temperature = temperature
        self.keyAlias = keyAlias
        self.localOnly = localOnly
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - ProviderRepositoryError

/// Errors raised by `ProviderRepositoryPort` implementations.
public enum ProviderRepositoryError: Error, Sendable {
    /// No profile exists for the given identifier.
    case profileNotFound(id: UUID)
    /// A `keyAlias` value was supplied that already exists in another profile.
    case duplicateKeyAlias(alias: String)
    /// The underlying persistence layer returned an error.
    case storageError(underlying: String)
    /// The port has not been registered in this process.
    case unimplemented
}

// MARK: - ProviderRepositoryPort

/// Port for reading and writing LLM provider profiles.
///
/// Declared in the domain core; implemented by `GRDBPersistenceAdapter`.
public protocol ProviderRepositoryPort: Sendable {
    /// Returns all provider profiles ordered by `displayName` ascending.
    func allProfiles() async throws -> [ProviderProfile]

    /// Returns the profile identified by `id`, or `nil` when absent.
    func profile(id: UUID) async throws -> ProviderProfile?

    /// Inserts a new provider profile record.
    ///
    /// - Throws: `ProviderRepositoryError.duplicateKeyAlias` when `keyAlias`
    ///   conflicts.
    func createProfile(_ profile: ProviderProfile) async throws

    /// Replaces the mutable fields of an existing profile.
    ///
    /// `id`, `createdAt`, and `keyAlias` are immutable; the adapter must
    /// reject mutations to them.
    ///
    /// - Throws: `ProviderRepositoryError.profileNotFound` when absent.
    func updateProfile(_ profile: ProviderProfile) async throws

    /// Deletes the profile and sets `chat_sessions.provider_profile_id = NULL`
    /// for any sessions that referenced it (referential delete action from
    /// DBML).
    ///
    /// - Throws: `ProviderRepositoryError.profileNotFound` when absent.
    func deleteProfile(id: UUID) async throws
}

// MARK: - UnimplementedProviderRepositoryPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedProviderRepositoryPort: ProviderRepositoryPort {
    public init() {}

    public func allProfiles() async throws -> [ProviderProfile] {
        throw ProviderRepositoryError.unimplemented
    }

    public func profile(id: UUID) async throws -> ProviderProfile? {
        throw ProviderRepositoryError.unimplemented
    }

    public func createProfile(_ profile: ProviderProfile) async throws {
        throw ProviderRepositoryError.unimplemented
    }

    public func updateProfile(_ profile: ProviderProfile) async throws {
        throw ProviderRepositoryError.unimplemented
    }

    public func deleteProfile(id: UUID) async throws {
        throw ProviderRepositoryError.unimplemented
    }
}
