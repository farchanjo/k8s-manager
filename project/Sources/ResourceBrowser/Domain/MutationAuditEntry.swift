// Domain/MutationAuditEntry.swift — resource_browser bounded context
// DDD role: ValueObject (immutable audit record)
// CUE source: docs/arch/contexts/resource_browser/schemas/mutation_audit_entry.cue
// ADR refs: ADR-0012 (audit log, tamper-evidence chain)

import Foundation

// MARK: - MutationOutcome

/// Outcome of a single mutation attempt.
///
/// Mirrors the `outcome` field of `#MutationAuditEntry`.
public enum MutationOutcome: String, Hashable, Sendable, Codable {
    /// The Kubernetes API returned 2xx and the mutation was applied.
    case succeeded
    /// The mutation guard policy denied the command before any API call.
    case denied
    /// The API returned an error status code, or a network error occurred.
    case failed
    /// The operator dismissed the confirmation modal before the API call.
    case cancelled
}

// MARK: - MutationAuditEntry

/// Immutable record of a single mutation attempt.
///
/// Written to the `cluster_mutation_audit` SQLite table (owned by
/// `local_persistence`) before the Kubernetes API call is dispatched. Rows are
/// never updated or deleted by the application.
///
/// SECURITY INVARIANT: MUST NOT contain credential material. Kubernetes API
/// tokens, client certificates, kubeconfig bearer tokens, exec-plugin output,
/// and Secret manifest values MUST NOT appear in any field. The command
/// serialiser is responsible for redacting sensitive values.
///
/// Mirrors `#MutationAuditEntry` from `mutation_audit_entry.cue`.
public struct MutationAuditEntry: Hashable, Sendable, Codable {
    /// UUIDv7 generated at command construction time.
    public let id: UUID

    /// RFC3339 timestamp when the command was constructed (before confirmation).
    public let requestedAt: String

    /// RFC3339 timestamp when the outcome was determined. `nil` until resolved.
    public let completedAt: String?

    /// UUIDv7 of the active cluster context at mutation request time.
    public let kubernetesContextId: UUID

    /// Serialised mutation command (sensitive values redacted).
    public let command: MutationCommand

    /// Final status of this mutation attempt.
    public let outcome: MutationOutcome

    /// HTTP status code returned by the Kubernetes API server.
    /// `nil` when no API call was made (denied or cancelled).
    public let kubernetesStatusCode: Int?

    /// SHA-256 hex digest of the YAML sent in the request body.
    /// Present only for `ApplyYAML` commands.
    public let manifestDigest: String?

    /// UUIDv7 generated when the confirmation modal was displayed.
    /// Links this audit entry to the specific operator gesture.
    public let confirmationToken: UUID

    /// HMAC-SHA256 hex digest linking this entry to the previous row
    /// in the tamper-evident chain (ADR-0012 MEDIUM-01, superseded by ADR-0047).
    /// Genesis row stores 64 zero hex characters.
    public let previousEntryDigest: String

    /// Keychain key generation used to produce `previousEntryDigest`.
    /// Defaults to `"v1"` (account `"chain-mac-key-v1"` in Keychain).
    public let keyVersion: String

    public init(
        id: UUID,
        requestedAt: String,
        completedAt: String? = nil,
        kubernetesContextId: UUID,
        command: MutationCommand,
        outcome: MutationOutcome,
        kubernetesStatusCode: Int? = nil,
        manifestDigest: String? = nil,
        confirmationToken: UUID,
        previousEntryDigest: String,
        keyVersion: String = "v1"
    ) {
        self.id = id
        self.requestedAt = requestedAt
        self.completedAt = completedAt
        self.kubernetesContextId = kubernetesContextId
        self.command = command
        self.outcome = outcome
        self.kubernetesStatusCode = kubernetesStatusCode
        self.manifestDigest = manifestDigest
        self.confirmationToken = confirmationToken
        self.previousEntryDigest = previousEntryDigest
        self.keyVersion = keyVersion
    }

    /// Sentinel `previousEntryDigest` for the genesis (first) audit row.
    public static let genesisDigest = String(repeating: "0", count: 64)
}
