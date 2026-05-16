// GRDBAuditChainStore.swift — GRDBPersistenceAdapter
// DDD role: RepositoryImpl + DomainService (secondary adapter — outbound to SQLite)
// Implements: AuditChainPort (LocalPersistence)
// ADR refs: ADR-0012 (mutating-operations policy), ADR-0047 (HMAC chain),
//           ADR-0010 (Keychain key access)

import Foundation
import GRDB
import LocalPersistence
import Logging

// MARK: - KeyProvider

/// Closure type that retrieves the raw HMAC key bytes from the Keychain.
///
/// Provided by `KeychainAdapter` at composition root. Returning `nil` means the
/// Keychain is locked or the item is absent.
public typealias KeyProvider = @Sendable () throws -> Data?

// MARK: - GRDBAuditChainStore

/// SQLite-backed, HMAC-authenticated implementation of ``AuditChainPort``.
///
/// The HMAC key is obtained on demand via `keyProvider` (injected at init) so
/// the Security framework never bleeds into this target.
public struct GRDBAuditChainStore: AuditChainPort {

    private let db: any DatabaseWriter
    private let keyProvider: KeyProvider
    private let logger: Logger

    // MARK: Init

    /// - Parameters:
    ///   - db: Shared `DatabaseQueue` / `DatabasePool`.
    ///   - keyProvider: Closure that returns the raw HMAC-SHA256 key bytes.
    ///   - logger: Diagnostics destination.
    public init(
        db: any DatabaseWriter,
        keyProvider: @escaping KeyProvider,
        logger: Logger = .init(label: "grdb.audit")
    ) {
        self.db = db
        self.keyProvider = keyProvider
        self.logger = logger
    }

    // MARK: AuditChainPort

    public func append(entry: AuditEntry) async throws {
        guard let key = try keyProvider() else {
            throw AuditChainError.keychainLocked
        }
        let precedingDigest = try await lastEntryDigest()
        let digest = try computeHMAC(key: key, previousDigest: precedingDigest, entry: entry)
        do {
            try await db.write { database in
                try insertAuditRow(entry: entry, digest: digest, in: database)
            }
        } catch {
            throw AuditChainError.storageError(underlying: error.localizedDescription)
        }
    }

    public func verifyPrecedingEntry(before entry: AuditEntry) async throws -> Bool {
        guard let key = try keyProvider() else {
            throw AuditChainError.keychainLocked
        }
        guard let preceding = try await fetchPrecedingEntry(before: entry) else {
            return true // Genesis — nothing to verify
        }
        guard let storedDigest = preceding.entryDigest else { return false }
        let recomputed = try computeHMAC(
            key: key,
            previousDigest: preceding.previousEntryDigest,
            entry: preceding
        )
        return recomputed == storedDigest
    }

    public func verifyFullChain() async throws -> AuditChainState {
        guard let key = try keyProvider() else {
            return .paused(reason: "Keychain locked")
        }
        let entries = try await fetchAllEntries()
        for entry in entries {
            guard let storedDigest = entry.entryDigest else {
                let state = AuditChainState.corrupt(
                    firstFailingEntryId: entry.id,
                    reason: "Missing entry digest"
                )
                return state
            }
            let recomputed = try computeHMAC(
                key: key,
                previousDigest: entry.previousEntryDigest,
                entry: entry
            )
            if recomputed != storedDigest {
                return .corrupt(
                    firstFailingEntryId: entry.id,
                    reason: "HMAC mismatch"
                )
            }
        }
        return .intact
    }

    public func currentState() async throws -> AuditChainState {
        // Lightweight: reads only the persisted chain_state from the most recent row.
        let stateString = try await db.read { database -> String? in
            try String.fetchOne(
                database,
                sql: """
                    SELECT chain_state FROM cluster_mutation_audit
                    ORDER BY requested_at DESC LIMIT 1
                    """
            )
        }
        return parseChainState(stateString ?? "intact")
    }

    // MARK: Private — GRDB helpers

    private func lastEntryDigest() async throws -> String {
        let digest = try await db.read { database -> String? in
            try String.fetchOne(
                database,
                sql: """
                    SELECT entry_digest FROM cluster_mutation_audit
                    ORDER BY requested_at DESC LIMIT 1
                    """
            )
        }
        return digest ?? AuditEntry.genesisDigest
    }

    private func fetchPrecedingEntry(before _: AuditEntry) async throws -> AuditEntry? {
        try await db.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: """
                    SELECT * FROM cluster_mutation_audit
                    ORDER BY requested_at DESC LIMIT 1
                    """
            ) else { return nil }
            return auditEntry(from: row)
        }
    }

    private func fetchAllEntries() async throws -> [AuditEntry] {
        try await db.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT * FROM cluster_mutation_audit ORDER BY requested_at ASC"
            )
            return rows.map(auditEntry(from:))
        }
    }

    // swiftlint:disable function_body_length
    private func insertAuditRow(entry: AuditEntry, digest: String, in database: Database) throws {
        try database.execute(
            sql: """
                INSERT INTO cluster_mutation_audit (
                    id, cluster_id, verb, gvk_group, gvk_version, gvk_kind,
                    namespace, resource_name, manifest_digest,
                    confirmation_token, confirmation_issued_at_seconds,
                    double_confirmed, requested_at, response_resource_version,
                    result, error_code, error_message,
                    previous_entry_digest, entry_digest, key_version
                ) VALUES (
                    ?, ?, ?, ?, ?, ?, ?, ?, ?,
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                )
                """,
            arguments: [
                entry.id.uuidString,
                entry.clusterId.uuidString,
                entry.verb.rawValue,
                entry.gvkGroup,
                entry.gvkVersion,
                entry.gvkKind,
                entry.namespace,
                entry.resourceName,
                entry.manifestDigest,
                entry.confirmationToken.uuidString,
                entry.confirmationIssuedAtSeconds,
                entry.doubleConfirmed ? 1 : 0,
                iso8601(entry.requestedAt),
                entry.responseResourceVersion,
                entry.result.rawValue,
                entry.errorCode,
                entry.errorMessage,
                entry.previousEntryDigest,
                digest,
                entry.keyVersion
            ]
        )
    }
    // swiftlint:enable function_body_length

    // MARK: Private — row mapping

    private func auditEntry(from row: Row) -> AuditEntry {
        AuditEntry(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            clusterId: UUID(uuidString: row["cluster_id"]) ?? UUID(),
            verb: AuditVerb(rawValue: row["verb"]) ?? .apply,
            gvkGroup: row["gvk_group"],
            gvkVersion: row["gvk_version"],
            gvkKind: row["gvk_kind"],
            namespace: row["namespace"],
            resourceName: row["resource_name"],
            manifestDigest: row["manifest_digest"],
            confirmationToken: UUID(uuidString: row["confirmation_token"]) ?? UUID(),
            confirmationIssuedAtSeconds: row["confirmation_issued_at_seconds"],
            doubleConfirmed: (row["double_confirmed"] as Int) != 0,
            requestedAt: parseDate(row["requested_at"]),
            responseResourceVersion: row["response_resource_version"],
            result: AuditResult(rawValue: row["result"]) ?? .failed,
            errorCode: row["error_code"],
            errorMessage: row["error_message"],
            previousEntryDigest: row["previous_entry_digest"],
            entryDigest: row["entry_digest"],
            keyVersion: row["key_version"] ?? "v1"
        )
    }

    // MARK: Private — HMAC

    /// Computes `HMAC-SHA256(key, previousDigest_hex || entryJSON_utf8)`.
    ///
    /// Uses only Foundation primitives to avoid importing CryptoKit here.
    /// The real implementation in production will use the key bytes from
    /// Keychain via the `keyProvider` closure.
    private func computeHMAC(key: Data, previousDigest: String, entry: AuditEntry) throws -> String {
        // Build canonical payload: previousDigest_hex + sorted JSON of core fields.
        let canonical = try canonicalJSON(for: entry)
        let payload = previousDigest + canonical
        guard let payloadData = payload.data(using: .utf8) else {
            throw AuditChainError.storageError(underlying: "UTF-8 encoding failed")
        }
        // Produce HMAC-SHA256 using CommonCrypto (available via Foundation on macOS).
        return hmacSHA256Hex(key: key, data: payloadData)
    }

    private func canonicalJSON(for entry: AuditEntry) throws -> String {
        let dict: [String: Any] = [
            "id": entry.id.uuidString,
            "cluster_id": entry.clusterId.uuidString,
            "verb": entry.verb.rawValue,
            "resource_name": entry.resourceName,
            "requested_at": iso8601(entry.requestedAt),
            "result": entry.result.rawValue
        ]
        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }

    // swiftlint:disable function_body_length
    private func hmacSHA256Hex(key: Data, data: Data) -> String {
        // CommonCrypto HMAC-SHA256 via the bridging header-free path on macOS 14+.
        // We use the cc_ symbols from libSystem which are always available on macOS.
        var result = [UInt8](repeating: 0, count: 32)
        key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmac(
                    kCCHmacAlgSHA256,
                    keyBytes.baseAddress, key.count,
                    dataBytes.baseAddress, data.count,
                    &result
                )
            }
        }
        return result.map { String(format: "%02x", $0) }.joined()
    }
    // swiftlint:enable function_body_length

    private func parseChainState(_ raw: String) -> AuditChainState {
        switch raw {
        case "intact": return .intact
        case let s where s.hasPrefix("paused:"): return .paused(reason: String(s.dropFirst(7)))
        default: return .intact
        }
    }

    // MARK: Date helpers

    private func iso8601(_ date: Date) -> String { iso8601String(date) }
    private func parseDate(_ string: String) -> Date { parseISO8601(string) }
}

// MARK: - CommonCrypto shim (no import needed — symbols from libSystem)

// swiftlint:disable identifier_name
private let kCCHmacAlgSHA256: UInt32 = 2
// swiftlint:enable identifier_name

@_silgen_name("CCHmac")
private func CCHmac(
    _ algorithm: UInt32,
    _ key: UnsafeRawPointer?,
    _ keyLength: Int,
    _ data: UnsafeRawPointer?,
    _ dataLength: Int,
    _ macOut: UnsafeMutableRawPointer?
)
