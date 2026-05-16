// Domain/KeychainEntry.swift — local_persistence bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/local_persistence/schemas/keychain_entry.cue
// ADR refs: ADR-0010 (Keychain placement), ADR-0018 (namespace partitioning)

import Foundation

// MARK: - KeychainServiceNamespace

/// The three Keychain service namespaces the application writes.
///
/// Mirrors the namespace-partitioning refinement in ADR-0010 §Refinement note.
/// All items are created with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// via the adapter; the domain value-object records the intent only.
public enum KeychainServiceNamespace: String, Hashable, Sendable, Codable {
    /// LLM API keys — `account` is the provider-profile key alias.
    case llm = "com.archanjo.K8sManager.llm"

    /// OIDC refresh tokens — `account` is the OIDC issuer URL.
    /// Service key is `"com.archanjo.K8sManager.oidc.<clusterId>"`.
    /// The cluster suffix is carried in ``KeychainEntry.serviceKeySuffix``.
    case oidc = "com.archanjo.K8sManager.oidc"

    /// Azure / MSAL tokens — `account` is the tenant identifier.
    /// Service key is `"com.archanjo.K8sManager.azure.<clusterId>"`.
    case azure = "com.archanjo.K8sManager.azure"

    /// Audit chain HMAC key — fixed singleton per ADR-0047.
    case audit = "com.archanjo.K8sManager.audit"
}

// MARK: - KeychainEntry

/// Value-object describing the shape of a single Keychain item managed by the
/// application.
///
/// The secret payload is **never** carried in this type. `KeychainEntry`
/// encodes only the item's locator attributes (service, account, label) and
/// invariant constraints declared in the CUE schema. The Security framework
/// adapter enforces `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` at write
/// time using these attributes.
///
/// Mirrors `#KeychainEntry` from `keychain_entry.cue`.
public struct KeychainEntry: Hashable, Sendable, Codable {
    /// The service namespace this entry belongs to.
    public let namespace: KeychainServiceNamespace

    /// Optional per-cluster suffix appended to the service string for OIDC and
    /// Azure namespaces (e.g. `"<clusterId>"`). `nil` for `.llm` and `.audit`.
    public let serviceKeySuffix: String?

    /// The `kSecAttrAccount` discriminator.
    ///
    /// For `.llm`: the provider-profile key alias (`^[a-z0-9][a-z0-9_-]*$`).
    /// For `.audit`: `"chain-mac-key-v1"` (or later version tags).
    /// For `.oidc`: the OIDC issuer URL.
    /// For `.azure`: the tenant identifier.
    public let account: String

    /// Human-readable label shown in Keychain Access.
    public let label: String

    /// Upper bound on the secret payload in bytes.
    ///
    /// Must be in the range `1...16_384` per `#KeychainEntry.genericPasswordSizeBytes`.
    public let maxPayloadBytes: Int

    /// The fully qualified `kSecAttrService` string, combining the namespace
    /// base value and the optional per-cluster suffix.
    public var serviceKey: String {
        guard let suffix = serviceKeySuffix, !suffix.isEmpty else {
            return namespace.rawValue
        }
        return "\(namespace.rawValue).\(suffix)"
    }

    public init(
        namespace: KeychainServiceNamespace,
        serviceKeySuffix: String? = nil,
        account: String,
        label: String,
        maxPayloadBytes: Int = 16_384
    ) {
        self.namespace = namespace
        self.serviceKeySuffix = serviceKeySuffix
        self.account = account
        self.label = label
        self.maxPayloadBytes = maxPayloadBytes
    }
}

// MARK: - KeychainEntry invariant checks

public extension KeychainEntry {
    /// Returns `true` when all domain invariants from `#KeychainEntry` hold.
    ///
    /// Called by adapters before performing Keychain writes; adapter MUST NOT
    /// write a non-valid entry.
    var isValid: Bool {
        !account.isEmpty
            && !label.isEmpty
            && (1...16_384).contains(maxPayloadBytes)
    }
}
