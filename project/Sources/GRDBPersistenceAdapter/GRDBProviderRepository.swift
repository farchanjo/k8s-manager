// GRDBProviderRepository.swift — GRDBPersistenceAdapter
// DDD role: RepositoryImpl (secondary adapter — outbound to SQLite)
// Implements: ProviderRepositoryPort (LocalPersistence)
// ADR refs: ADR-0008, ADR-0010

import Foundation
import GRDB
import LocalPersistence
import Logging

// MARK: - GRDBProviderRepository

/// SQLite-backed implementation of ``ProviderRepositoryPort``.
public struct GRDBProviderRepository: ProviderRepositoryPort {

    private let db: any DatabaseWriter
    private let logger: Logger

    // MARK: Init

    public init(db: any DatabaseWriter, logger: Logger = .init(label: "grdb.provider")) {
        self.db = db
        self.logger = logger
    }

    // MARK: ProviderRepositoryPort

    public func allProfiles() async throws -> [ProviderProfile] {
        try await db.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT * FROM provider_profiles ORDER BY display_name ASC"
            )
            return rows.map(providerProfile(from:))
        }
    }

    public func profile(id: UUID) async throws -> ProviderProfile? {
        try await db.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM provider_profiles WHERE id = ?",
                arguments: [id.uuidString]
            ) else { return nil }
            return providerProfile(from: row)
        }
    }

    public func createProfile(_ profile: ProviderProfile) async throws {
        do {
            try await db.write { database in
                try database.execute(
                    sql: """
                        INSERT INTO provider_profiles
                            (id, kind, display_name, endpoint_url, model,
                             temperature, key_alias, local_only, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        profile.id.uuidString,
                        profile.kind.rawValue,
                        profile.displayName,
                        profile.endpointURL,
                        profile.model,
                        profile.temperature,
                        profile.keyAlias,
                        profile.localOnly ? 1 : 0,
                        Self.iso8601(profile.createdAt),
                        Self.iso8601(profile.updatedAt)
                    ]
                )
            }
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            throw ProviderRepositoryError.duplicateKeyAlias(alias: profile.keyAlias)
        } catch {
            throw ProviderRepositoryError.storageError(underlying: error.localizedDescription)
        }
    }

    public func updateProfile(_ profile: ProviderProfile) async throws {
        do {
            let count = try await db.write { database -> Int in
                try database.execute(
                    sql: """
                        UPDATE provider_profiles
                        SET kind = ?, display_name = ?, endpoint_url = ?, model = ?,
                            temperature = ?, local_only = ?, updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        profile.kind.rawValue,
                        profile.displayName,
                        profile.endpointURL,
                        profile.model,
                        profile.temperature,
                        profile.localOnly ? 1 : 0,
                        Self.iso8601(profile.updatedAt),
                        profile.id.uuidString
                    ]
                )
                return database.changesCount
            }
            if count == 0 { throw ProviderRepositoryError.profileNotFound(id: profile.id) }
        } catch let err as ProviderRepositoryError {
            throw err
        } catch {
            throw ProviderRepositoryError.storageError(underlying: error.localizedDescription)
        }
    }

    public func deleteProfile(id: UUID) async throws {
        let count = try await db.write { database -> Int in
            try database.execute(
                sql: "DELETE FROM provider_profiles WHERE id = ?",
                arguments: [id.uuidString]
            )
            return database.changesCount
        }
        if count == 0 { throw ProviderRepositoryError.profileNotFound(id: id) }
    }

    // MARK: Row mapping

    private func providerProfile(from row: Row) -> ProviderProfile {
        ProviderProfile(
            id: UUID(uuidString: row["id"]) ?? UUID(),
            kind: ProviderKind(rawValue: row["kind"]) ?? .anthropic,
            displayName: row["display_name"],
            endpointURL: row["endpoint_url"],
            model: row["model"],
            temperature: row["temperature"],
            keyAlias: row["key_alias"],
            localOnly: (row["local_only"] as Int) != 0,
            createdAt: Self.parseDate(row["created_at"]),
            updatedAt: Self.parseDate(row["updated_at"])
        )
    }

    // MARK: Date helpers

    private static func iso8601Formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private static func iso8601(_ date: Date) -> String {
        Self.iso8601Formatter().string(from: date)
    }

    private static func parseDate(_ string: String) -> Date {
        Self.iso8601Formatter().date(from: string) ?? Date(timeIntervalSince1970: 0)
    }
}
