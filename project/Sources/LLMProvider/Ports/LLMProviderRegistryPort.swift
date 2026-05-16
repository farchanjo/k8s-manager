// Ports/LLMProviderRegistryPort.swift — llm_provider bounded context
// DDD role: Port (secondary — outbound to local_persistence)
// Narrative ref: domain/narrative.md §Read models exposed to other contexts

import Foundation

// MARK: - LLMProviderRegistryPort

/// CRUD operations and read-model projections over the `ProviderProfile`
/// aggregate.
///
/// Declared in the domain core; implemented by `GRDBPersistenceAdapter` in
/// infrastructure. The domain core never imports GRDB.
public protocol LLMProviderRegistryPort: Sendable {
    /// Fetches all configured provider profiles ordered by `displayName`.
    ///
    /// - Returns: Ordered list of profiles. Empty when no profiles are saved.
    /// - Throws: `LLMRegistryError` on storage failure.
    func allProfiles() async throws -> [ProviderProfile]

    /// Fetches a single profile by its stable identifier.
    ///
    /// - Parameter id: The `ProviderProfile.id` to resolve.
    /// - Returns: The matching profile.
    /// - Throws: `LLMRegistryError.notFound` when no profile has that `id`.
    func profile(id: UUID) async throws -> ProviderProfile

    /// Persists a new profile or replaces an existing one with the same `id`.
    ///
    /// - Parameter profile: The aggregate root to upsert.
    /// - Throws: `LLMRegistryError` on constraint or storage failure.
    func upsert(_ profile: ProviderProfile) async throws

    /// Removes the profile identified by `id`.
    ///
    /// - Parameter id: Stable identifier of the profile to delete.
    /// - Throws: `LLMRegistryError.notFound` when `id` is unknown.
    func delete(id: UUID) async throws

    /// Returns the flat list read model consumed by `app_shell`.
    ///
    /// - Returns: A `ProviderListReadModel` with zero or more rows.
    /// - Throws: `LLMRegistryError` on storage failure.
    func listReadModel() async throws -> ProviderListReadModel

    /// Returns the capability snapshot for `profileId`, or `nil` when no
    /// feature-detection probe has completed for that profile.
    ///
    /// - Parameter profileId: The profile whose capabilities are requested.
    /// - Returns: A `ProviderCapabilityReadModel`, or `nil`.
    /// - Throws: `LLMRegistryError` on storage failure.
    func capabilityReadModel(profileId: UUID) async throws -> ProviderCapabilityReadModel?

    /// Persists or updates the capability snapshot for `profileId`.
    ///
    /// - Parameter model: The capability snapshot to store.
    /// - Throws: `LLMRegistryError` on storage failure.
    func upsertCapability(_ model: ProviderCapabilityReadModel) async throws
}

// MARK: - LLMRegistryError

/// Errors raised by `LLMProviderRegistryPort` implementations.
public enum LLMRegistryError: Error, Sendable {
    /// No profile exists for the requested identifier.
    case notFound(UUID)

    /// A uniqueness constraint was violated (e.g., duplicate `displayName`).
    case constraintViolation(detail: String)

    /// A storage-layer error occurred.
    case storageError(detail: String)

    /// The port has not been registered in this process.
    case unimplemented
}

// MARK: - UnimplementedLLMProviderRegistryPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedLLMProviderRegistryPort: LLMProviderRegistryPort {
    public init() {}

    public func allProfiles() async throws -> [ProviderProfile] {
        throw LLMRegistryError.unimplemented
    }

    public func profile(id: UUID) async throws -> ProviderProfile {
        throw LLMRegistryError.unimplemented
    }

    public func upsert(_ profile: ProviderProfile) async throws {
        throw LLMRegistryError.unimplemented
    }

    public func delete(id: UUID) async throws {
        throw LLMRegistryError.unimplemented
    }

    public func listReadModel() async throws -> ProviderListReadModel {
        throw LLMRegistryError.unimplemented
    }

    public func capabilityReadModel(profileId: UUID) async throws -> ProviderCapabilityReadModel? {
        throw LLMRegistryError.unimplemented
    }

    public func upsertCapability(_ model: ProviderCapabilityReadModel) async throws {
        throw LLMRegistryError.unimplemented
    }
}
