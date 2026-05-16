// Domain/SecretRevealEntry.swift — local_persistence bounded context
// DDD role: Entity (append-only, secret_reveal_audit table projection)
// DBML source: docs/arch/contexts/local_persistence/schemas/storage.dbml
//              §secret_reveal_audit
// ADR refs: ADR-0063 (secret reveal/hide + dockerconfigjson parser),
//           ADR-0047 (HMAC-SHA256 chain)

import Foundation

// MARK: - SecretRevealAction

/// The operator-initiated or system-generated action recorded in the audit.
///
/// Mirrors the `action` column constraint in `storage.dbml §secret_reveal_audit`.
public enum SecretRevealAction: String, Hashable, Sendable, Codable {
    /// Operator clicked the eye icon to reveal a key.
    case reveal          = "reveal"
    /// Operator clicked the eye icon again to hide a revealed key.
    case hide            = "hide"
    /// Operator clicked the copy icon while a key was revealed.
    case clipboardCopy   = "clipboard-copy"
    /// The 60-second focus-loss timer fired and auto-hid revealed keys.
    case autoHide        = "auto-hide"
}

// MARK: - SecretRevealEntry

/// Immutable projection of one row in the `secret_reveal_audit` table.
///
/// This entity records privileged Secret data access events. Per ADR-0063,
/// **the decoded secret value is never stored** — only the access metadata.
/// The HMAC chain links entries within this table independently from the
/// `cluster_mutation_audit` chain (ADR-0047).
public struct SecretRevealEntry: Hashable, Sendable, Codable {

    /// UUIDv7 primary key.
    public let id: UUID

    /// UUIDv7 of the cluster whose Secret was accessed.
    public let clusterId: UUID

    /// Namespace of the accessed Secret.
    public let namespace: String

    /// `metadata.name` of the accessed Secret.
    public let secretName: String

    /// The `type` field from the Secret's metadata
    /// (e.g. `"kubernetes.io/dockerconfigjson"`).
    public let secretType: String

    /// The specific key in the Secret's `data` map that was accessed.
    ///
    /// Deep-reveal paths use dotted notation per ADR-0063 §Special type parsers,
    /// e.g. `".dockerconfigjson.auths.registry-io.password"`.
    public let keyName: String

    /// The action that triggered this audit entry.
    public let action: SecretRevealAction

    /// The `NSUserName()` value at the time of the action.
    public let userIdentifier: String

    /// RFC 3339 UTC timestamp when the action occurred.
    public let requestedAt: Date

    /// 64-character lowercase HMAC-SHA256 hex chain link to the prior row.
    ///
    /// Sentinel value `"0" * 64` for the genesis row (ADR-0047 §Genesis row).
    /// Independent chain — links only to prior `secret_reveal_audit` rows,
    /// never to `cluster_mutation_audit` rows.
    public let previousEntryDigest: String

    /// 64-character lowercase HMAC-SHA256 tag for this entry.
    ///
    /// Populated by the adapter; `nil` until the write completes.
    public let entryDigest: String?

    /// Creates a `SecretRevealEntry`.
    public init(
        id: UUID,
        clusterId: UUID,
        namespace: String,
        secretName: String,
        secretType: String,
        keyName: String,
        action: SecretRevealAction,
        userIdentifier: String,
        requestedAt: Date,
        previousEntryDigest: String,
        entryDigest: String? = nil
    ) {
        self.id = id
        self.clusterId = clusterId
        self.namespace = namespace
        self.secretName = secretName
        self.secretType = secretType
        self.keyName = keyName
        self.action = action
        self.userIdentifier = userIdentifier
        self.requestedAt = requestedAt
        self.previousEntryDigest = previousEntryDigest
        self.entryDigest = entryDigest
    }
}

// MARK: - SecretRevealEntry invariant checks

public extension SecretRevealEntry {

    /// The sentinel digest used for the genesis row (ADR-0047 §Genesis row).
    static let genesisDigest = String(repeating: "0", count: 64)

    /// Returns `true` when structural invariants from the schema and ADR-0047
    /// hold.
    ///
    /// Does not verify HMAC correctness — that requires the secret key
    /// and is the responsibility of `SecretRevealAuditPort`.
    var isStructurallyValid: Bool {
        !namespace.isEmpty
            && !secretName.isEmpty
            && !keyName.isEmpty
            && !userIdentifier.isEmpty
            && previousEntryDigest.count == 64
            && previousEntryDigest.allSatisfy { $0.isHexDigit }
            && (entryDigest == nil || (entryDigest!.count == 64 && entryDigest!.allSatisfy { $0.isHexDigit }))
    }
}
