// Domain/AuditChainKey.swift — local_persistence bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/local_persistence/schemas/audit_chain_key.cue
// ADR refs: ADR-0047 (HMAC-SHA256 audit chain), ADR-0010 (Keychain policy)

import Foundation

// MARK: - AuditChainKey

/// Value-object describing the Keychain item that holds the HMAC-SHA256 key
/// used to authenticate the mutation-audit chain.
///
/// The key material itself is **never** present here — it lives exclusively in
/// the macOS Keychain. This type carries only the locator attributes that
/// `AuditChainKeyManager` uses to create or look up the item.
///
/// Mirrors `#AuditChainKey` from `audit_chain_key.cue`.
///
/// Current canonical instance: ``AuditChainKey.v1``.
public struct AuditChainKey: Hashable, Sendable, Codable {
    /// `kSecAttrService` value; distinct from the LLM key namespace to prevent
    /// namespace collisions in Keychain Access.
    ///
    /// Fixed at `"com.archanjo.K8sManager.audit"` for all generations.
    public let service: String

    /// `kSecAttrAccount` discriminator. Matches `^chain-mac-key-v[0-9]+$`.
    ///
    /// Incremented for each key rotation generation.
    public let account: String

    /// MAC algorithm for which this key is used.
    ///
    /// Fixed at `"HMAC-SHA256"` for v1; future generations may use
    /// `"HMAC-SHA512"`.
    public let algorithm: String

    /// Key material length in bits. Must be 256 for HMAC-SHA256.
    public let keyLengthBits: Int

    /// Monotonically increasing generation counter matching the suffix in
    /// ``account``. Starts at 1.
    public let keyVersion: Int

    /// Human-readable label for Keychain Access.
    ///
    /// Matches `^K8sManager audit chain MAC key - v[0-9]+$`.
    public let label: String

    public init(
        service: String,
        account: String,
        algorithm: String,
        keyLengthBits: Int,
        keyVersion: Int,
        label: String
    ) {
        self.service = service
        self.account = account
        self.algorithm = algorithm
        self.keyLengthBits = keyLengthBits
        self.keyVersion = keyVersion
        self.label = label
    }

    // MARK: - Canonical instances

    /// The first-generation audit chain MAC key (ADR-0047 §Specification).
    public static let v1 = AuditChainKey(
        service: "com.archanjo.K8sManager.audit",
        account: "chain-mac-key-v1",
        algorithm: "HMAC-SHA256",
        keyLengthBits: 256,
        keyVersion: 1,
        label: "K8sManager audit chain MAC key - v1"
    )
}

// MARK: - AuditChainKey invariant checks

public extension AuditChainKey {
    /// Returns `true` when all CUE-declared invariants hold.
    var isValid: Bool {
        service == "com.archanjo.K8sManager.audit"
            && account.hasPrefix("chain-mac-key-v")
            && keyLengthBits == 256
            && keyVersion >= 1
    }
}
