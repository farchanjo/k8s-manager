// AuditChainKeyManager.swift — actor managing the HMAC-SHA256 audit chain key
// ADR refs: ADR-0047 (HMAC chain key generation/storage), ADR-0010 (Keychain policy)
// Key spec: 256-bit random, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
//           service="com.archanjo.K8sManager.audit", account="chain-mac-key-v1"

import Foundation
import Security
import LocalPersistence

// MARK: - AuditChainKeyManager

/// Actor that lazily generates and persists the HMAC-SHA256 audit chain key
/// per ADR-0047.
///
/// On first call to ``currentKey()`` the actor looks up the Keychain item for
/// ``AuditChainKey.v1``. If absent it generates 256 bits of cryptographically
/// random data via `SecRandomCopyBytes`, stores the item, and returns the bytes.
/// Subsequent calls return the cached value without touching the Keychain.
///
/// Thread safety: actor isolation guarantees exactly-once generation.
public actor AuditChainKeyManager {
    private let keychainAdapter: any KeychainAccessPort
    private var cachedKey: Data?

    /// Creates a manager backed by the given Keychain adapter.
    ///
    /// - Parameter keychainAdapter: Port implementation used for reads and
    ///   writes. Defaults to ``KeychainAccessAdapter`` (live production value).
    public init(keychainAdapter: any KeychainAccessPort = KeychainAccessAdapter()) {
        self.keychainAdapter = keychainAdapter
    }

    // MARK: - Public API

    /// Returns the current HMAC-SHA256 key for the audit chain.
    ///
    /// On first invocation reads or generates the 256-bit key and stores it in
    /// the macOS Keychain. Subsequent calls return the in-memory cached value.
    ///
    /// - Throws: `KeychainAccessError` when the Keychain is locked or an
    ///   unexpected Security framework error occurs.
    public func currentKey() async throws -> Data {
        if let key = cachedKey { return key }
        let key = try await resolveOrCreateKey()
        cachedKey = key
        return key
    }

    /// Returns a `@Sendable` async closure that provides the current HMAC key.
    ///
    /// Suitable for injection as `keyProvider` into `GRDBAuditChainStore`.
    public nonisolated func keyProvider() -> @Sendable () async throws -> Data {
        { [weak self] in
            guard let self else { throw KeychainAccessError.unimplemented }
            return try await self.currentKey()
        }
    }

    // MARK: - Private helpers

    private func resolveOrCreateKey() async throws -> Data {
        let entry = auditKeyEntry()
        do {
            return try await keychainAdapter.readSecret(for: entry)
        } catch KeychainAccessError.itemNotFound {
            return try await generateAndStore(entry: entry)
        }
    }

    private func generateAndStore(entry: KeychainEntry) async throws -> Data {
        let key = try generateRandomKey()
        try await keychainAdapter.writeSecret(key, for: entry)
        return key
    }

    private func generateRandomKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            throw KeychainAccessError.securityError(
                status: result,
                detail: "SecRandomCopyBytes failed"
            )
        }
        return Data(bytes)
    }

    private func auditKeyEntry() -> KeychainEntry {
        let spec = AuditChainKey.v1
        return KeychainEntry(
            namespace: .audit,
            account: spec.account,
            label: spec.label,
            maxPayloadBytes: spec.keyLengthBits / 8
        )
    }
}
