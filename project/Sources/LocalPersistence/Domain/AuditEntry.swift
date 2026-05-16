// Domain/AuditEntry.swift — local_persistence bounded context
// DDD role: Entity (append-only, cluster_mutation_audit table projection)
// DBML source: docs/arch/contexts/local_persistence/schemas/storage.dbml
//              §cluster_mutation_audit
// ADR refs: ADR-0012 (mutating-operations policy),
//           ADR-0047 (HMAC-SHA256 chain)

import Foundation

// MARK: - AuditVerb

/// Kubernetes mutation verbs recorded in the audit chain.
///
/// Mirrors the `verb` column constraint in `storage.dbml`.
public enum AuditVerb: String, Hashable, Sendable, Codable {
    case apply           = "apply"
    case patch           = "patch"
    case delete          = "delete"
    case scale           = "scale"
    case rolloutRestart  = "rollout-restart"
    case create          = "create"
}

// MARK: - AuditResult

/// Outcome of a Kubernetes mutation operation.
///
/// Mirrors the `result` column constraint in `storage.dbml`.
public enum AuditResult: String, Hashable, Sendable, Codable {
    case success  = "success"
    case conflict = "conflict"
    case failed   = "failed"
}

// MARK: - AuditEntry

/// Immutable projection of one row in the `cluster_mutation_audit` table.
///
/// This domain entity is the append-only audit record for every operator-
/// initiated Kubernetes mutation. It carries both the structural chain link
/// (`previousEntryDigest`) and the HMAC tag (`entryDigest`) introduced by
/// ADR-0047.
///
/// The domain core does not compute HMAC — that is the responsibility of the
/// `AuditChainPort` in the infrastructure layer. The domain only defines the
/// shape and invariants of the record.
public struct AuditEntry: Hashable, Sendable, Codable {
    /// UUIDv7 primary key.
    public let id: UUID

    /// UUIDv7 of the target cluster. No FK — cluster registry lives outside
    /// SQLite.
    public let clusterId: UUID

    /// The mutation verb.
    public let verb: AuditVerb

    /// Kubernetes API group. Empty string for `core/v1`.
    public let gvkGroup: String

    /// Kubernetes API version, e.g. `"v1"` or `"apps/v1"`.
    public let gvkVersion: String

    /// Kubernetes resource kind, e.g. `"Deployment"`.
    public let gvkKind: String

    /// Namespace. `nil` for cluster-scoped resources.
    public let namespace: String?

    /// `metadata.name` of the target resource.
    public let resourceName: String

    /// SHA-256 hex of the submitted manifest payload. Empty for non-manifest
    /// verbs (delete, scale).
    public let manifestDigest: String

    /// UUIDv7 issued by the confirmation modal.
    public let confirmationToken: UUID

    /// Unix epoch seconds when the confirmation token was issued.
    public let confirmationIssuedAtSeconds: Int64

    /// `true` after the second confirmation step for destructive verbs.
    public let doubleConfirmed: Bool

    /// RFC 3339 UTC timestamp when the mutation was dispatched to the
    /// Kubernetes API.
    public let requestedAt: Date

    /// `resourceVersion` returned by the API server on success. `nil` on
    /// failure.
    public let responseResourceVersion: String?

    /// Operation outcome.
    public let result: AuditResult

    /// HTTP or Kubernetes status code as a string on failure (e.g. `"409"`).
    /// `nil` on success.
    public let errorCode: String?

    /// API server error body. Must not contain credential material.
    public let errorMessage: String?

    /// 64-character lowercase hex HMAC-SHA256 of the previous entry's digest.
    ///
    /// Sentinel value `"0" * 64` for the genesis row (ADR-0047 §Genesis row).
    public let previousEntryDigest: String

    /// 64-character lowercase hex HMAC-SHA256 tag for this entry.
    ///
    /// Computed as:
    /// `HMAC-SHA256(key, previousEntryDigest_hex || canonicalEntryJSON_utf8)`.
    ///
    /// Populated by the adapter via `AuditChainPort`; `nil` until the write
    /// completes.
    public let entryDigest: String?

    /// Key version tag matching the Keychain item used to compute
    /// `entryDigest`. Defaults to `"v1"` (ADR-0047 §Key version tracking).
    public let keyVersion: String

    public init(
        id: UUID,
        clusterId: UUID,
        verb: AuditVerb,
        gvkGroup: String,
        gvkVersion: String,
        gvkKind: String,
        namespace: String?,
        resourceName: String,
        manifestDigest: String,
        confirmationToken: UUID,
        confirmationIssuedAtSeconds: Int64,
        doubleConfirmed: Bool,
        requestedAt: Date,
        responseResourceVersion: String?,
        result: AuditResult,
        errorCode: String?,
        errorMessage: String?,
        previousEntryDigest: String,
        entryDigest: String? = nil,
        keyVersion: String = "v1"
    ) {
        self.id = id
        self.clusterId = clusterId
        self.verb = verb
        self.gvkGroup = gvkGroup
        self.gvkVersion = gvkVersion
        self.gvkKind = gvkKind
        self.namespace = namespace
        self.resourceName = resourceName
        self.manifestDigest = manifestDigest
        self.confirmationToken = confirmationToken
        self.confirmationIssuedAtSeconds = confirmationIssuedAtSeconds
        self.doubleConfirmed = doubleConfirmed
        self.requestedAt = requestedAt
        self.responseResourceVersion = responseResourceVersion
        self.result = result
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.previousEntryDigest = previousEntryDigest
        self.entryDigest = entryDigest
        self.keyVersion = keyVersion
    }
}

// MARK: - AuditEntry invariant checks

public extension AuditEntry {
    /// The sentinel digest used for the genesis row (ADR-0047 §Genesis row).
    static let genesisDigest = String(repeating: "0", count: 64)

    /// Returns `true` when structural invariants from the schema and ADR-0047
    /// hold.
    ///
    /// Does **not** verify HMAC correctness — that requires the secret key
    /// and is the responsibility of `AuditChainPort`.
    var isStructurallyValid: Bool {
        !resourceName.isEmpty
            && !gvkKind.isEmpty
            && !gvkVersion.isEmpty
            && previousEntryDigest.count == 64
            && previousEntryDigest.allSatisfy { $0.isHexDigit }
            && (entryDigest == nil || (entryDigest!.count == 64 && entryDigest!.allSatisfy { $0.isHexDigit }))
    }
}
