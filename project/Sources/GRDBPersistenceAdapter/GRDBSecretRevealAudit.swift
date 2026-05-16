// GRDBSecretRevealAudit.swift — GRDBPersistenceAdapter
// DDD role: RepositoryImpl (secondary adapter — outbound to SQLite)
// Implements: SecretRevealAuditPort (LocalPersistence)
// ADR refs: ADR-0063 (secret reveal/hide + dockerconfigjson parser),
//           ADR-0047 (HMAC-SHA256 chain), ADR-0010 (Keychain key access)

import Foundation
import GRDB
import LocalPersistence
import Logging

// MARK: - GRDBSecretRevealAudit

/// SQLite-backed, HMAC-authenticated implementation of ``SecretRevealAuditPort``.
///
/// Uses the same `KeyProvider` type as ``GRDBAuditChainStore`` so that both
/// chains share the same Keychain-stored HMAC key
/// (`com.archanjo.K8sManager.audit`) per ADR-0047.
public struct GRDBSecretRevealAudit: SecretRevealAuditPort {

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
        logger: Logger = .init(label: "grdb.secret-reveal-audit")
    ) {
        self.db = db
        self.keyProvider = keyProvider
        self.logger = logger
    }

    // MARK: SecretRevealAuditPort

    public func append(entry: SecretRevealEntry) async throws -> UUID {
        guard let key = try keyProvider() else {
            throw SecretRevealAuditError.keychainLocked
        }
        let precedingDigest = try await lastEntryDigest()
        let digest = try computeHMAC(key: key, previousDigest: precedingDigest, entry: entry)
        do {
            try await db.write { database in
                try insertRow(entry: entry, previousDigest: precedingDigest, digest: digest, in: database)
            }
        } catch {
            throw SecretRevealAuditError.storageError(underlying: error.localizedDescription)
        }
        logger.debug("secret_reveal_audit: appended \(entry.action.rawValue) for \(entry.keyName)")
        return entry.id
    }

    // MARK: Private — GRDB helpers

    private func lastEntryDigest() async throws -> String {
        let digest = try await db.read { database -> String? in
            try String.fetchOne(
                database,
                sql: """
                    SELECT entry_digest FROM secret_reveal_audit
                    ORDER BY requested_at DESC LIMIT 1
                    """
            )
        }
        return digest ?? SecretRevealEntry.genesisDigest
    }

    private func insertRow(
        entry: SecretRevealEntry,
        previousDigest: String,
        digest: String,
        in database: Database
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO secret_reveal_audit (
                    id, cluster_id, namespace, secret_name, secret_type,
                    key_name, action, user_identifier, requested_at,
                    previous_entry_digest, entry_digest
                ) VALUES (
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                )
                """,
            arguments: [
                entry.id.uuidString,
                entry.clusterId.uuidString,
                entry.namespace,
                entry.secretName,
                entry.secretType,
                entry.keyName,
                entry.action.rawValue,
                entry.userIdentifier,
                iso8601String(entry.requestedAt),
                previousDigest,
                digest
            ]
        )
    }

    // MARK: Private — HMAC

    /// Computes `HMAC-SHA256(key, previousDigest_hex || entryJSON_utf8)`.
    private func computeHMAC(key: Data, previousDigest: String, entry: SecretRevealEntry) throws -> String {
        let canonical = canonicalJSON(for: entry)
        let payload = previousDigest + canonical
        guard let payloadData = payload.data(using: .utf8) else {
            throw SecretRevealAuditError.storageError(underlying: "UTF-8 encoding failed")
        }
        return hmacSHA256Hex(key: key, data: payloadData)
    }

    private func canonicalJSON(for entry: SecretRevealEntry) -> String {
        let dict: [String: Any] = [
            "id": entry.id.uuidString,
            "cluster_id": entry.clusterId.uuidString,
            "namespace": entry.namespace,
            "secret_name": entry.secretName,
            "key_name": entry.keyName,
            "action": entry.action.rawValue,
            "requested_at": iso8601String(entry.requestedAt)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    // swiftlint:disable function_body_length
    private func hmacSHA256Hex(key: Data, data: Data) -> String {
        var result = [UInt8](repeating: 0, count: 32)
        key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                CCHmacReveal(
                    kCCHmacAlgSHA256Reveal,
                    keyBytes.baseAddress, key.count,
                    dataBytes.baseAddress, data.count,
                    &result
                )
            }
        }
        return result.map { String(format: "%02x", $0) }.joined()
    }
    // swiftlint:enable function_body_length
}

// MARK: - CommonCrypto shim (libSystem symbols — no import needed)

// swiftlint:disable identifier_name
private let kCCHmacAlgSHA256Reveal: UInt32 = 2
// swiftlint:enable identifier_name

@_silgen_name("CCHmac")
private func CCHmacReveal(
    _ algorithm: UInt32,
    _ key: UnsafeRawPointer?,
    _ keyLength: Int,
    _ data: UnsafeRawPointer?,
    _ dataLength: Int,
    _ macOut: UnsafeMutableRawPointer?
)
