// Ports/SecretRevealAuditPort.swift — local_persistence bounded context
// DDD role: Port (secondary — outbound to persistence + Security framework)
// Consumed by: app_shell / resource_browser bounded contexts
// ADR refs: ADR-0063 (secret reveal/hide + dockerconfigjson parser),
//           ADR-0047 (HMAC-SHA256 audit chain)

import Foundation

// MARK: - SecretRevealAuditError

/// Errors raised by `SecretRevealAuditPort` implementations.
public enum SecretRevealAuditError: Error, Sendable {
    /// The Keychain is locked; the HMAC key cannot be read.
    case keychainLocked
    /// The Keychain item for the audit key was not found.
    case keyNotFound
    /// A write was rejected because the chain is in a corrupt state.
    case chainCorrupt
    /// The underlying persistence layer returned an error.
    case storageError(underlying: String)
    /// The port has not been registered in this process.
    case unimplemented
}

// MARK: - SecretRevealAuditPort

/// Port for appending entries to the HMAC-gated secret-reveal audit chain.
///
/// Declared in the domain core; implemented by an adapter that combines GRDB
/// (for row storage) and the Security framework (for HMAC key access). The
/// domain core imports neither.
///
/// Per ADR-0047, the HMAC digest is computed as:
/// ```
/// entryDigest = HMAC-SHA256(key, previousEntryDigest_hex || canonicalEntryJSON_utf8)
/// ```
///
/// The chain is independent from `AuditChainPort` / `cluster_mutation_audit`.
/// Each table links only to its own prior rows.
public protocol SecretRevealAuditPort: Sendable {

    /// Appends `entry` to the `secret_reveal_audit` table, computing and
    /// storing its HMAC tag.
    ///
    /// The adapter reads the preceding entry's `entry_digest` (or the genesis
    /// sentinel `"0" * 64` for the first row), computes the HMAC, and writes
    /// the row atomically.
    ///
    /// - Returns: The `UUID` of the persisted entry.
    /// - Throws: `SecretRevealAuditError.keychainLocked` when the HMAC key
    ///   is inaccessible.
    func append(entry: SecretRevealEntry) async throws -> UUID
}

// MARK: - UnimplementedSecretRevealAuditPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedSecretRevealAuditPort: SecretRevealAuditPort {
    public init() {}

    public func append(entry: SecretRevealEntry) async throws -> UUID {
        throw SecretRevealAuditError.unimplemented
    }
}
