// GRDBPersistenceAdapterTests.swift — GRDBPersistenceAdapterTests
// Coverage: migration, chat session round-trip, provider profile insert/list,
//           cluster metadata upsert/expiry, audit entry append + readback.

import XCTest
import Foundation
import GRDB
@testable import GRDBPersistenceAdapter
import LocalPersistence

// MARK: - GRDBPersistenceAdapterTests

final class GRDBPersistenceAdapterTests: XCTestCase {

    // MARK: - Shared in-memory bundle

    private var bundle: GRDBPersistenceAdapter.PersistenceBundle!

    override func setUp() async throws {
        try await super.setUp()
        let queue = try DatabaseQueue()
        let key = Data(repeating: 0xAB, count: 32)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v3_all") { db in
            try SchemaMigrator._runV3(db)
        }
        try migrator.migrate(queue)
        bundle = GRDBPersistenceAdapter.PersistenceBundle(
            chatRepository: GRDBChatRepository(db: queue),
            providerRepository: GRDBProviderRepository(db: queue),
            clusterMetadataStore: GRDBClusterMetadataStore(db: queue),
            auditChainStore: GRDBAuditChainStore(db: queue, keyProvider: { key }),
            terminalRepository: GRDBTerminalRepository(db: queue),
            secretRevealAudit: GRDBSecretRevealAudit(db: queue, keyProvider: { key }),
            prometheusEndpointRepository: GRDBPrometheusEndpointRepository(db: queue)
        )
    }

    // MARK: - 1. Migration applies cleanly

    func test_migration_applies_without_error() throws {
        // setUp() completes without throwing iff all migrations succeeded.
        XCTAssertNotNil(bundle)
    }

    // MARK: - 2. Chat session round-trip

    func test_createSession_then_session_byId_returns_same_fields() async throws {
        let session = makeSession(title: "Hello cluster")

        try await bundle.chatRepository.createSession(session)
        let fetched = try await bundle.chatRepository.session(id: session.id)

        let unwrapped = try XCTUnwrap(fetched)
        XCTAssertEqual(unwrapped.id, session.id)
        XCTAssertEqual(unwrapped.title, "Hello cluster")
        XCTAssertNil(unwrapped.archivedAt)
    }

    // MARK: - 3. activeSessions excludes archived

    func test_activeSessions_excludes_archived_sessions() async throws {
        let active = makeSession(title: "Active")
        let archived = makeSession(title: "Archived")

        try await bundle.chatRepository.createSession(active)
        try await bundle.chatRepository.createSession(archived)
        try await bundle.chatRepository.archiveSession(id: archived.id, at: Date())

        let results = try await bundle.chatRepository.activeSessions()
        XCTAssertTrue(results.contains(where: { $0.id == active.id }))
        XCTAssertFalse(results.contains(where: { $0.id == archived.id }))
    }

    // MARK: - 4. updateSessionTitle

    func test_updateSessionTitle_changes_title() async throws {
        let session = makeSession(title: nil)
        try await bundle.chatRepository.createSession(session)

        try await bundle.chatRepository.updateSessionTitle(id: session.id, title: "Updated")

        let fetched = try await bundle.chatRepository.session(id: session.id)
        XCTAssertEqual(fetched?.title, "Updated")
    }

    // MARK: - 5. appendMessage + messages round-trip

    func test_appendMessage_and_messages_roundtrip() async throws {
        let session = makeSession()
        try await bundle.chatRepository.createSession(session)

        let msg = ChatMessage(
            id: UUID(),
            sessionId: session.id,
            role: .user,
            content: "What is the cluster status?",
            createdAt: Date()
        )
        try await bundle.chatRepository.appendMessage(msg)

        let messages = try await bundle.chatRepository.messages(sessionId: session.id)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].content, "What is the cluster status?")
        XCTAssertEqual(messages[0].role, .user)
    }

    // MARK: - 6. Provider profile insert + list

    func test_createProfile_appears_in_allProfiles() async throws {
        let profile = makeProfile(displayName: "GPT-4")
        try await bundle.providerRepository.createProfile(profile)

        let all = try await bundle.providerRepository.allProfiles()
        XCTAssertTrue(all.contains(where: { $0.id == profile.id }))
    }

    // MARK: - 7. Provider profile deleteProfile removes record

    func test_deleteProfile_removes_from_allProfiles() async throws {
        let profile = makeProfile(displayName: "Anthropic Claude")
        try await bundle.providerRepository.createProfile(profile)
        try await bundle.providerRepository.deleteProfile(id: profile.id)

        let all = try await bundle.providerRepository.allProfiles()
        XCTAssertFalse(all.contains(where: { $0.id == profile.id }))
    }

    // MARK: - 8. Cluster metadata upsert + read

    func test_upsertAnalysis_then_cachedAnalysis_returns_entry() async throws {
        let clusterId = UUID()
        let entry = makeAnalysisCache(clusterId: clusterId, kind: .clusterSummary)

        try await bundle.clusterMetadataStore.upsertAnalysis(entry)

        let cached = try await bundle.clusterMetadataStore.cachedAnalysis(
            clusterId: clusterId,
            kind: .clusterSummary,
            now: Date()
        )
        let unwrapped = try XCTUnwrap(cached)
        XCTAssertEqual(unwrapped.id, entry.id)
        XCTAssertEqual(unwrapped.payloadJSON, entry.payloadJSON)
    }

    // MARK: - 9. pruneExpired removes expired entries

    func test_pruneExpired_removes_expired_entries() async throws {
        let clusterId = UUID()
        let expired = makeAnalysisCache(
            clusterId: clusterId,
            kind: .nodePressure,
            expiresAt: Date(timeIntervalSinceNow: -3600)
        )
        try await bundle.clusterMetadataStore.upsertAnalysis(expired)

        let deleted = try await bundle.clusterMetadataStore.pruneExpired(now: Date())
        XCTAssertEqual(deleted, 1)

        let result = try await bundle.clusterMetadataStore.cachedAnalysis(
            clusterId: clusterId,
            kind: .nodePressure,
            now: Date()
        )
        XCTAssertNil(result)
    }

    // MARK: - 10. Cluster metadata upsert replaces prior entry

    func test_upsertAnalysis_replaces_prior_entry_for_same_cluster_and_kind() async throws {
        let clusterId = UUID()
        let first = makeAnalysisCache(clusterId: clusterId, kind: .rolloutHistory, payload: "v1")
        let second = makeAnalysisCache(clusterId: clusterId, kind: .rolloutHistory, payload: "v2")

        try await bundle.clusterMetadataStore.upsertAnalysis(first)
        try await bundle.clusterMetadataStore.upsertAnalysis(second)

        let cached = try await bundle.clusterMetadataStore.cachedAnalysis(
            clusterId: clusterId,
            kind: .rolloutHistory,
            now: Date()
        )
        XCTAssertEqual(cached?.payloadJSON, "v2")
    }

    // MARK: - 11. Audit entry append + currentState is intact

    func test_append_audit_entry_then_currentState_is_intact() async throws {
        let entry = makeAuditEntry()
        try await bundle.auditChainStore.append(entry: entry)

        let state = try await bundle.auditChainStore.currentState()
        if case .intact = state { return }
        XCTFail("Expected .intact, got \(state)")
    }

    // MARK: - 12. verifyFullChain on empty store returns intact

    func test_verifyFullChain_on_empty_store_returns_intact() async throws {
        let state = try await bundle.auditChainStore.verifyFullChain()
        if case .intact = state { return }
        XCTFail("Expected .intact on empty chain, got \(state)")
    }

    // MARK: - Helpers

    private func makeSession(title: String? = nil) -> ChatSession {
        ChatSession(
            id: UUID(),
            createdAt: Date(),
            updatedAt: Date(),
            title: title
        )
    }

    private func makeProfile(displayName: String) -> ProviderProfile {
        ProviderProfile(
            id: UUID(),
            kind: .anthropic,
            displayName: displayName,
            endpointURL: "https://api.anthropic.com",
            model: "claude-opus-4-7",
            keyAlias: "alias-\(UUID().uuidString)",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeAnalysisCache(
        clusterId: UUID,
        kind: AnalysisKind,
        payload: String = #"{"status":"ok"}"#,
        expiresAt: Date = Date(timeIntervalSinceNow: 3600)
    ) -> ClusterAnalysisCache {
        ClusterAnalysisCache(
            id: UUID(),
            clusterId: clusterId,
            kind: kind,
            payloadJSON: payload,
            expiresAt: expiresAt,
            createdAt: Date()
        )
    }

    private func makeAuditEntry() -> AuditEntry {
        AuditEntry(
            id: UUID(),
            clusterId: UUID(),
            verb: .apply,
            gvkGroup: "apps",
            gvkVersion: "v1",
            gvkKind: "Deployment",
            namespace: "default",
            resourceName: "nginx",
            manifestDigest: String(repeating: "a", count: 64),
            confirmationToken: UUID(),
            confirmationIssuedAtSeconds: Int64(Date().timeIntervalSince1970),
            doubleConfirmed: false,
            requestedAt: Date(),
            responseResourceVersion: nil,
            result: .success,
            errorCode: nil,
            errorMessage: nil,
            previousEntryDigest: AuditEntry.genesisDigest
        )
    }
}
