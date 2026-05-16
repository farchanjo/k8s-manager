// Ports/LLMKeyStorePort.swift — llm_provider bounded context
// DDD role: Port (secondary — outbound to Keychain infrastructure)
// Narrative ref: domain/narrative.md §Tactical roles — LLMKeyResolverPort

import Foundation

// MARK: - LLMKeyStorePort

/// Reads provider API key values from the system Keychain.
///
/// Declared in the domain core; the default adapter lives in
/// `KeychainAdapter` / `local_persistence`. API key values MUST NOT appear
/// in any log entry, telemetry payload, or diagnostics export — callers
/// are responsible for not retaining the returned value beyond the HTTP
/// request lifetime.
public protocol LLMKeyStorePort: Sendable {
    /// Resolves the secret value associated with `alias` from the Keychain.
    ///
    /// - Parameter alias: The `keyAlias` field from a `ProviderProfile`.
    /// - Returns: The secret string value.
    /// - Throws: `LLMKeyStoreError` when the alias is unknown or the
    ///   Keychain read fails.
    func secret(for alias: String) async throws -> String

    /// Persists or updates a secret in the Keychain under `alias`.
    ///
    /// - Parameters:
    ///   - secret: The API key value. MUST NOT be logged by implementations.
    ///   - alias: The stable Keychain entry name.
    /// - Throws: `LLMKeyStoreError` on Keychain write failure.
    func store(secret: String, for alias: String) async throws

    /// Removes the Keychain entry for `alias`.
    ///
    /// - Parameter alias: The `keyAlias` from a `ProviderProfile`.
    /// - Throws: `LLMKeyStoreError` when the alias is unknown or the deletion
    ///   fails.
    func delete(alias: String) async throws
}

// MARK: - LLMKeyStoreError

/// Errors raised by `LLMKeyStorePort` implementations.
public enum LLMKeyStoreError: Error, Sendable {
    /// No Keychain entry exists for the given alias.
    case notFound(alias: String)

    /// The Keychain operation was denied (e.g., access group mismatch).
    case accessDenied(detail: String)

    /// An unexpected Keychain status code was returned.
    case keychainError(status: Int32)

    /// The port has not been registered in this process.
    case unimplemented
}

// MARK: - UnimplementedLLMKeyStorePort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedLLMKeyStorePort: LLMKeyStorePort {
    public init() {}

    public func secret(for alias: String) async throws -> String {
        throw LLMKeyStoreError.unimplemented
    }

    public func store(secret: String, for alias: String) async throws {
        throw LLMKeyStoreError.unimplemented
    }

    public func delete(alias: String) async throws {
        throw LLMKeyStoreError.unimplemented
    }
}
