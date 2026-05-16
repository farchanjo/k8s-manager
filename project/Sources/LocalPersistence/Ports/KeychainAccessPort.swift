// Ports/KeychainAccessPort.swift — local_persistence bounded context
// DDD role: Port (secondary — outbound to Security framework)
// Consumed by: llm_provider bounded context (API key reads via KeychainAdapter)
// Narrative ref: domain/narrative.md §Tactical roles
// ADR refs: ADR-0010 (Keychain placement and namespacing),
//           ADR-0018 (OIDC/Azure namespace extension)

import Foundation

// MARK: - KeychainAccessError

/// Errors raised by `KeychainAccessPort` implementations.
public enum KeychainAccessError: Error, Sendable {
    /// The Keychain item for the given entry was not found.
    case itemNotFound(entry: KeychainEntry)
    /// The Keychain is locked; the item could not be read or written.
    case keychainLocked
    /// The caller lacks the access group or entitlement required.
    case accessDenied(detail: String)
    /// A write was rejected because the entry fails domain invariants.
    case invalidEntry(violations: [String])
    /// The Security framework returned an unexpected error code.
    case securityError(status: Int32, detail: String)
    /// The port has not been registered in this process.
    case unimplemented
}

// MARK: - KeychainAccessPort

/// Port for reading, writing, and deleting secret payloads from the macOS
/// Keychain.
///
/// Declared in the domain core; implemented by `KeychainAdapter` which imports
/// the Security framework. The domain core never imports Security.
///
/// All writes enforce `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (ADR-0010
/// invariant). The adapter MUST reject any entry that specifies a less
/// restrictive accessibility class.
public protocol KeychainAccessPort: Sendable {
    /// Reads the secret payload for the given `entry`.
    ///
    /// - Returns: The raw secret bytes.
    /// - Throws: `KeychainAccessError.itemNotFound` when absent,
    ///   `KeychainAccessError.keychainLocked` when the screen is locked.
    func readSecret(for entry: KeychainEntry) async throws -> Data

    /// Writes (creates or updates) the secret payload for `entry`.
    ///
    /// - Throws: `KeychainAccessError.invalidEntry` when
    ///   `entry.isValid == false`.
    func writeSecret(_ secret: Data, for entry: KeychainEntry) async throws

    /// Deletes the Keychain item for `entry`.
    ///
    /// No-ops if the item is already absent.
    func deleteSecret(for entry: KeychainEntry) async throws

    /// Returns all Keychain items under the given service namespace.
    ///
    /// Used by the "delete local data" flow to enumerate and remove every
    /// entry in a namespace (ADR-0010 §Backups and reset).
    func listEntries(
        namespace: KeychainServiceNamespace
    ) async throws -> [KeychainEntry]
}

// MARK: - UnimplementedKeychainAccessPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedKeychainAccessPort: KeychainAccessPort {
    public init() {}

    public func readSecret(for entry: KeychainEntry) async throws -> Data {
        throw KeychainAccessError.unimplemented
    }

    public func writeSecret(_ secret: Data, for entry: KeychainEntry) async throws {
        throw KeychainAccessError.unimplemented
    }

    public func deleteSecret(for entry: KeychainEntry) async throws {
        throw KeychainAccessError.unimplemented
    }

    public func listEntries(
        namespace: KeychainServiceNamespace
    ) async throws -> [KeychainEntry] {
        throw KeychainAccessError.unimplemented
    }
}
