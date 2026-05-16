// Ports/AuditChainPort.swift — local_persistence bounded context
// DDD role: Port (secondary — outbound to persistence + Security framework)
// Consumed by: resource_browser bounded context
// Narrative ref: domain/narrative.md §Tactical roles
// ADR refs: ADR-0047 (HMAC-SHA256 audit chain),
//           ADR-0012 (mutating-operations policy)

import Foundation

// MARK: - AuditChainState

/// Current integrity state of the mutation audit chain.
public enum AuditChainState: Hashable, Sendable, Codable {
    /// All entries in the chain have been verified; HMAC tags are intact.
    case intact

    /// The Keychain is locked; verification has been paused until the
    /// operator unlocks the screen (ADR-0047 §Key unavailability).
    case paused(reason: String)

    /// At least one entry failed HMAC verification; new writes are suspended
    /// until an operator acknowledges the corruption.
    case corrupt(firstFailingEntryId: UUID, reason: String)

    /// The Keychain item was absent (fresh install, wipe, or migration). A
    /// new genesis entry has been written with a freshly generated key.
    /// Prior entries remain readable but their HMAC tags are unverifiable.
    case reseeded(newGenesisEntryId: UUID)
}

// MARK: - AuditChainError

/// Errors raised by `AuditChainPort` implementations.
public enum AuditChainError: Error, Sendable {
    /// The Keychain is locked; the HMAC key cannot be read.
    case keychainLocked
    /// The Keychain item for the audit key was not found.
    case keyNotFound
    /// A write was rejected because the chain is in a `corrupt` state.
    case chainCorrupt
    /// The underlying persistence layer returned an error.
    case storageError(underlying: String)
    /// The port has not been registered in this process.
    case unimplemented
}

// MARK: - AuditChainPort

/// Port for appending entries to the HMAC-gated mutation audit chain and
/// verifying chain integrity.
///
/// Declared in the domain core; implemented by an adapter that combines GRDB
/// (for row storage) and the Security framework (for HMAC key access). The
/// domain core imports neither.
///
/// Per ADR-0047, the HMAC digest is computed as:
/// ```
/// entryDigest = HMAC-SHA256(key, previousEntryDigest_hex || canonicalEntryJSON_utf8)
/// ```
public protocol AuditChainPort: Sendable {
    /// Appends `entry` to the audit table, computing and storing its
    /// HMAC tag.
    ///
    /// The adapter reads the preceding entry's `entryDigest` (or the genesis
    /// sentinel `"0" * 64` for the first row), computes the HMAC, and writes
    /// the row atomically.
    ///
    /// - Throws: `AuditChainError.keychainLocked` when the HMAC key is
    ///   inaccessible; `AuditChainError.chainCorrupt` when a prior corruption
    ///   has suspended writes.
    func append(entry: AuditEntry) async throws

    /// Verifies the HMAC tag of the single entry immediately preceding `entry`.
    ///
    /// Called before each write to satisfy the ADR-0047 per-write verification
    /// contract without walking the full chain.
    ///
    /// - Returns: `true` when the preceding entry's HMAC is intact, `false`
    ///   when it fails verification.
    /// - Throws: `AuditChainError.keychainLocked` when the key is inaccessible.
    func verifyPrecedingEntry(before entry: AuditEntry) async throws -> Bool

    /// Walks and verifies every entry in the audit chain.
    ///
    /// Returns the current `AuditChainState`. On integrity failure the state
    /// is persisted so that subsequent calls and writes observe the corrupt
    /// state without re-walking.
    func verifyFullChain() async throws -> AuditChainState

    /// Returns the current chain state without performing a full walk.
    ///
    /// Reads the persisted state written by the most recent `verifyFullChain`
    /// call or a write-time verification that detected corruption.
    func currentState() async throws -> AuditChainState
}

// MARK: - UnimplementedAuditChainPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedAuditChainPort: AuditChainPort {
    public init() {}

    public func append(entry: AuditEntry) async throws {
        throw AuditChainError.unimplemented
    }

    public func verifyPrecedingEntry(before entry: AuditEntry) async throws -> Bool {
        throw AuditChainError.unimplemented
    }

    public func verifyFullChain() async throws -> AuditChainState {
        throw AuditChainError.unimplemented
    }

    public func currentState() async throws -> AuditChainState {
        throw AuditChainError.unimplemented
    }
}
