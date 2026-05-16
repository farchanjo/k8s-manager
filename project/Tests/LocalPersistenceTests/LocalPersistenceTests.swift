// Tests/LocalPersistenceTests/LocalPersistenceTests.swift
// XCTest suite for the LocalPersistence domain core.
//
// Coverage areas:
//   1. KeychainEntry — invariant validation, serviceKey construction
//   2. AuditChainKey — canonical v1 instance, invariant validation
//   3. PersistenceStore — invariant validation
//   4. PersistenceMigration — invariant validation
//   5. AuditEntry — structural invariants, genesis sentinel
//   6. Port sentinels — all Unimplemented* ports throw .unimplemented
//   7. DependencyValues — keys resolve to sentinel implementations

import XCTest
import Dependencies
@testable import LocalPersistence

// MARK: - KeychainEntryTests

final class KeychainEntryTests: XCTestCase {

    func test_validLLMEntry_isValid() {
        let entry = KeychainEntry(
            namespace: .llm,
            account: "my-provider-1",
            label: "K8sManager LLM key - my-provider-1"
        )
        XCTAssertTrue(entry.isValid)
    }

    func test_emptyAccount_isInvalid() {
        let entry = KeychainEntry(
            namespace: .llm,
            account: "",
            label: "K8sManager LLM key - x"
        )
        XCTAssertFalse(entry.isValid)
    }

    func test_emptyLabel_isInvalid() {
        let entry = KeychainEntry(
            namespace: .llm,
            account: "alias",
            label: ""
        )
        XCTAssertFalse(entry.isValid)
    }

    func test_zeroMaxPayloadBytes_isInvalid() {
        let entry = KeychainEntry(
            namespace: .llm,
            account: "alias",
            label: "label",
            maxPayloadBytes: 0
        )
        XCTAssertFalse(entry.isValid)
    }

    func test_overLimitMaxPayloadBytes_isInvalid() {
        let entry = KeychainEntry(
            namespace: .llm,
            account: "alias",
            label: "label",
            maxPayloadBytes: 16_385
        )
        XCTAssertFalse(entry.isValid)
    }

    func test_serviceKey_withoutSuffix_equalsNamespaceRawValue() {
        let entry = KeychainEntry(namespace: .llm, account: "a", label: "l")
        XCTAssertEqual(entry.serviceKey, "com.archanjo.K8sManager.llm")
    }

    func test_serviceKey_withSuffix_appendsClusterId() {
        let entry = KeychainEntry(
            namespace: .oidc,
            serviceKeySuffix: "cluster-uuid-here",
            account: "https://issuer.example",
            label: "OIDC token"
        )
        XCTAssertEqual(entry.serviceKey, "com.archanjo.K8sManager.oidc.cluster-uuid-here")
    }

    func test_serviceKey_withEmptySuffix_equalsNamespaceRawValue() {
        let entry = KeychainEntry(
            namespace: .azure,
            serviceKeySuffix: "",
            account: "tenant",
            label: "Azure token"
        )
        XCTAssertEqual(entry.serviceKey, "com.archanjo.K8sManager.azure")
    }

    func test_auditNamespace_rawValue() {
        XCTAssertEqual(KeychainServiceNamespace.audit.rawValue, "com.archanjo.K8sManager.audit")
    }
}

// MARK: - AuditChainKeyTests

final class AuditChainKeyTests: XCTestCase {

    func test_v1_isValid() {
        XCTAssertTrue(AuditChainKey.v1.isValid)
    }

    func test_v1_service() {
        XCTAssertEqual(AuditChainKey.v1.service, "com.archanjo.K8sManager.audit")
    }

    func test_v1_account() {
        XCTAssertEqual(AuditChainKey.v1.account, "chain-mac-key-v1")
    }

    func test_v1_algorithm() {
        XCTAssertEqual(AuditChainKey.v1.algorithm, "HMAC-SHA256")
    }

    func test_v1_keyLengthBits() {
        XCTAssertEqual(AuditChainKey.v1.keyLengthBits, 256)
    }

    func test_v1_keyVersion() {
        XCTAssertEqual(AuditChainKey.v1.keyVersion, 1)
    }

    func test_v1_label() {
        XCTAssertEqual(AuditChainKey.v1.label, "K8sManager audit chain MAC key - v1")
    }

    func test_wrongService_isInvalid() {
        let key = AuditChainKey(
            service: "com.other.service",
            account: "chain-mac-key-v1",
            algorithm: "HMAC-SHA256",
            keyLengthBits: 256,
            keyVersion: 1,
            label: "K8sManager audit chain MAC key - v1"
        )
        XCTAssertFalse(key.isValid)
    }

    func test_128BitKey_isInvalid() {
        let key = AuditChainKey(
            service: "com.archanjo.K8sManager.audit",
            account: "chain-mac-key-v1",
            algorithm: "HMAC-SHA256",
            keyLengthBits: 128,
            keyVersion: 1,
            label: "K8sManager audit chain MAC key - v1"
        )
        XCTAssertFalse(key.isValid)
    }

    func test_zeroKeyVersion_isInvalid() {
        let key = AuditChainKey(
            service: "com.archanjo.K8sManager.audit",
            account: "chain-mac-key-v0",
            algorithm: "HMAC-SHA256",
            keyLengthBits: 256,
            keyVersion: 0,
            label: "K8sManager audit chain MAC key - v0"
        )
        XCTAssertFalse(key.isValid)
    }

    func test_codableRoundtrip() throws {
        let encoded = try JSONEncoder().encode(AuditChainKey.v1)
        let decoded = try JSONDecoder().decode(AuditChainKey.self, from: encoded)
        XCTAssertEqual(decoded, AuditChainKey.v1)
    }
}

// MARK: - PersistenceStoreTests

final class PersistenceStoreTests: XCTestCase {

    private func makeStore(
        path: String = "/Users/test/.config/k8smanager/storage.sqlite3",
        schemaVersion: Int = 1
    ) -> PersistenceStore {
        PersistenceStore(
            id: UUID(),
            storageFilePath: path,
            schemaVersion: schemaVersion
        )
    }

    func test_validStore_isValid() {
        XCTAssertTrue(makeStore().isValid)
    }

    func test_relativePath_isInvalid() {
        XCTAssertFalse(makeStore(path: "relative/path.sqlite3").isValid)
    }

    func test_zeroSchemaVersion_isInvalid() {
        XCTAssertFalse(makeStore(schemaVersion: 0).isValid)
    }

    func test_journalModeIsAlwaysWAL() {
        XCTAssertEqual(makeStore().journalMode, "wal")
    }

    func test_lastVacuumAt_nilByDefault() {
        XCTAssertNil(makeStore().lastVacuumAt)
    }

    func test_codableRoundtrip() throws {
        let store = makeStore(schemaVersion: 3)
        let encoded = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(PersistenceStore.self, from: encoded)
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertEqual(decoded.journalMode, "wal")
    }
}

// MARK: - PersistenceMigrationTests

final class PersistenceMigrationTests: XCTestCase {

    private let validChecksum = String(repeating: "a", count: 64)

    func test_validMigration_isValid() {
        let m = PersistenceMigration(
            version: 1,
            appliedAt: Date(),
            description: "v1_initial_schema",
            checksumSHA256: validChecksum
        )
        XCTAssertTrue(m.isValid)
    }

    func test_zeroVersion_isInvalid() {
        let m = PersistenceMigration(
            version: 0,
            appliedAt: Date(),
            description: "zero",
            checksumSHA256: validChecksum
        )
        XCTAssertFalse(m.isValid)
    }

    func test_emptyDescription_isInvalid() {
        let m = PersistenceMigration(
            version: 1,
            appliedAt: Date(),
            description: "",
            checksumSHA256: validChecksum
        )
        XCTAssertFalse(m.isValid)
    }

    func test_shortChecksum_isInvalid() {
        let m = PersistenceMigration(
            version: 1,
            appliedAt: Date(),
            description: "desc",
            checksumSHA256: "abc"
        )
        XCTAssertFalse(m.isValid)
    }

    func test_nonHexChecksum_isInvalid() {
        let badChecksum = String(repeating: "z", count: 64)
        let m = PersistenceMigration(
            version: 1,
            appliedAt: Date(),
            description: "desc",
            checksumSHA256: badChecksum
        )
        XCTAssertFalse(m.isValid)
    }
}

// MARK: - AuditEntryTests

final class AuditEntryTests: XCTestCase {

    private func makeEntry(
        previousDigest: String = AuditEntry.genesisDigest,
        resourceName: String = "my-deployment",
        gvkKind: String = "Deployment",
        gvkVersion: String = "apps/v1"
    ) -> AuditEntry {
        AuditEntry(
            id: UUID(),
            clusterId: UUID(),
            verb: .apply,
            gvkGroup: "apps",
            gvkVersion: gvkVersion,
            gvkKind: gvkKind,
            namespace: "default",
            resourceName: resourceName,
            manifestDigest: String(repeating: "b", count: 64),
            confirmationToken: UUID(),
            confirmationIssuedAtSeconds: 1_700_000_000,
            doubleConfirmed: false,
            requestedAt: Date(),
            responseResourceVersion: "12345",
            result: .success,
            errorCode: nil,
            errorMessage: nil,
            previousEntryDigest: previousDigest
        )
    }

    func test_genesisDigestIs64Zeros() {
        XCTAssertEqual(AuditEntry.genesisDigest, String(repeating: "0", count: 64))
        XCTAssertEqual(AuditEntry.genesisDigest.count, 64)
    }

    func test_validEntry_isStructurallyValid() {
        XCTAssertTrue(makeEntry().isStructurallyValid)
    }

    func test_emptyResourceName_isInvalid() {
        XCTAssertFalse(makeEntry(resourceName: "").isStructurallyValid)
    }

    func test_emptyGvkKind_isInvalid() {
        XCTAssertFalse(makeEntry(gvkKind: "").isStructurallyValid)
    }

    func test_emptyGvkVersion_isInvalid() {
        XCTAssertFalse(makeEntry(gvkVersion: "").isStructurallyValid)
    }

    func test_shortPreviousDigest_isInvalid() {
        XCTAssertFalse(makeEntry(previousDigest: "abc").isStructurallyValid)
    }

    func test_nonHexPreviousDigest_isInvalid() {
        let badDigest = String(repeating: "z", count: 64)
        XCTAssertFalse(makeEntry(previousDigest: badDigest).isStructurallyValid)
    }

    func test_entryDigestNilByDefault() {
        XCTAssertNil(makeEntry().entryDigest)
    }

    func test_validEntryDigest_passesValidation() {
        let entry = AuditEntry(
            id: UUID(),
            clusterId: UUID(),
            verb: .delete,
            gvkGroup: "",
            gvkVersion: "v1",
            gvkKind: "Pod",
            namespace: "kube-system",
            resourceName: "my-pod",
            manifestDigest: "",
            confirmationToken: UUID(),
            confirmationIssuedAtSeconds: 0,
            doubleConfirmed: true,
            requestedAt: Date(),
            responseResourceVersion: nil,
            result: .success,
            errorCode: nil,
            errorMessage: nil,
            previousEntryDigest: AuditEntry.genesisDigest,
            entryDigest: String(repeating: "c", count: 64),
            keyVersion: "v1"
        )
        XCTAssertTrue(entry.isStructurallyValid)
    }

    func test_invalidEntryDigestLength_isInvalid() {
        let entry = AuditEntry(
            id: UUID(),
            clusterId: UUID(),
            verb: .scale,
            gvkGroup: "apps",
            gvkVersion: "v1",
            gvkKind: "Deployment",
            namespace: "default",
            resourceName: "my-dep",
            manifestDigest: "",
            confirmationToken: UUID(),
            confirmationIssuedAtSeconds: 0,
            doubleConfirmed: false,
            requestedAt: Date(),
            responseResourceVersion: nil,
            result: .failed,
            errorCode: "409",
            errorMessage: nil,
            previousEntryDigest: AuditEntry.genesisDigest,
            entryDigest: "tooshort",
            keyVersion: "v1"
        )
        XCTAssertFalse(entry.isStructurallyValid)
    }

    func test_codableRoundtrip() throws {
        let entry = makeEntry()
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(AuditEntry.self, from: encoded)
        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.verb, entry.verb)
        XCTAssertEqual(decoded.previousEntryDigest, AuditEntry.genesisDigest)
    }
}

// MARK: - PortSentinelTests

final class PortSentinelTests: XCTestCase {

    // MARK: ChatRepositoryPort

    func test_unimplementedChatRepository_activeSessions_throws() async {
        let port = UnimplementedChatRepositoryPort()
        await assertUnimplemented { try await port.activeSessions() }
    }

    func test_unimplementedChatRepository_appendMessage_throws() async {
        let port = UnimplementedChatRepositoryPort()
        let msg = ChatMessage(
            id: UUID(),
            sessionId: UUID(),
            role: .user,
            content: "hello",
            createdAt: Date()
        )
        await assertUnimplemented { try await port.appendMessage(msg) }
    }

    // MARK: ProviderRepositoryPort

    func test_unimplementedProviderRepository_allProfiles_throws() async {
        let port = UnimplementedProviderRepositoryPort()
        await assertUnimplemented { try await port.allProfiles() }
    }

    // MARK: ClusterMetadataStorePort

    func test_unimplementedClusterMetadata_cachedAnalysis_throws() async {
        let port = UnimplementedClusterMetadataStorePort()
        await assertUnimplemented {
            _ = try await port.cachedAnalysis(clusterId: UUID(), kind: .clusterSummary, now: Date())
        }
    }

    func test_unimplementedClusterMetadata_pruneExpired_throws() async {
        let port = UnimplementedClusterMetadataStorePort()
        await assertUnimplemented { _ = try await port.pruneExpired(now: Date()) }
    }

    // MARK: KeychainAccessPort

    func test_unimplementedKeychain_readSecret_throws() async {
        let port = UnimplementedKeychainAccessPort()
        let entry = KeychainEntry(namespace: .llm, account: "a", label: "l")
        await assertUnimplemented { _ = try await port.readSecret(for: entry) }
    }

    func test_unimplementedKeychain_listEntries_throws() async {
        let port = UnimplementedKeychainAccessPort()
        await assertUnimplemented { _ = try await port.listEntries(namespace: .llm) }
    }

    // MARK: AuditChainPort

    func test_unimplementedAuditChain_append_throws() async {
        let port = UnimplementedAuditChainPort()
        let entry = makeMinimalAuditEntry()
        await assertUnimplemented { try await port.append(entry: entry) }
    }

    func test_unimplementedAuditChain_verifyFullChain_throws() async {
        let port = UnimplementedAuditChainPort()
        await assertUnimplemented { _ = try await port.verifyFullChain() }
    }

    func test_unimplementedAuditChain_currentState_throws() async {
        let port = UnimplementedAuditChainPort()
        await assertUnimplemented { _ = try await port.currentState() }
    }
}

// MARK: - DependencyValuesTests

final class DependencyValuesTests: XCTestCase {

    func test_chatRepositoryDefault_isUnimplemented() async {
        await withDependencies { _ in } operation: {
            @Dependency(\.chatRepository) var repo
            await assertUnimplemented { try await repo.activeSessions() }
        }
    }

    func test_providerRepositoryDefault_isUnimplemented() async {
        await withDependencies { _ in } operation: {
            @Dependency(\.providerRepository) var repo
            await assertUnimplemented { try await repo.allProfiles() }
        }
    }

    func test_keychainAccessDefault_isUnimplemented() async {
        await withDependencies { _ in } operation: {
            @Dependency(\.keychainAccess) var port
            let entry = KeychainEntry(namespace: .llm, account: "x", label: "y")
            await assertUnimplemented { _ = try await port.readSecret(for: entry) }
        }
    }

    func test_auditChainDefault_isUnimplemented() async {
        await withDependencies { _ in } operation: {
            @Dependency(\.auditChain) var port
            await assertUnimplemented { _ = try await port.currentState() }
        }
    }

    func test_clusterMetadataStoreDefault_isUnimplemented() async {
        await withDependencies { _ in } operation: {
            @Dependency(\.clusterMetadataStore) var store
            await assertUnimplemented {
                _ = try await store.cachedAnalysis(
                    clusterId: UUID(),
                    kind: .nodePressure,
                    now: Date()
                )
            }
        }
    }
}

// MARK: - Test helpers

/// Asserts that the async throwing closure throws any `.unimplemented` case
/// from the local persistence port error enums.
private func assertUnimplemented(
    _ block: @escaping @Sendable () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await block()
        XCTFail("Expected an unimplemented error; none was thrown", file: file, line: line)
    } catch is UnimplementedPortError {
        // pass — sentinel matched via protocol below
    } catch let error as ChatRepositoryError where error == .unimplemented {
        // pass
    } catch let error as ProviderRepositoryError where error == .unimplemented {
        // pass
    } catch let error as ClusterMetadataStoreError where error == .unimplemented {
        // pass
    } catch let error as KeychainAccessError where error == .unimplemented {
        // pass
    } catch let error as AuditChainError where error == .unimplemented {
        // pass
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}

/// Marker protocol so the helper above can be extended without enumerating
/// every error type each time a new port is added.
private protocol UnimplementedPortError {}

private func makeMinimalAuditEntry() -> AuditEntry {
    AuditEntry(
        id: UUID(),
        clusterId: UUID(),
        verb: .apply,
        gvkGroup: "apps",
        gvkVersion: "v1",
        gvkKind: "Deployment",
        namespace: "default",
        resourceName: "test-deploy",
        manifestDigest: String(repeating: "a", count: 64),
        confirmationToken: UUID(),
        confirmationIssuedAtSeconds: 0,
        doubleConfirmed: false,
        requestedAt: Date(),
        responseResourceVersion: nil,
        result: .success,
        errorCode: nil,
        errorMessage: nil,
        previousEntryDigest: AuditEntry.genesisDigest
    )
}

// MARK: - Error equatability for sentinel checks

extension ChatRepositoryError: Equatable {
    public static func == (lhs: ChatRepositoryError, rhs: ChatRepositoryError) -> Bool {
        switch (lhs, rhs) {
        case (.unimplemented, .unimplemented): return true
        default: return false
        }
    }
}

extension ProviderRepositoryError: Equatable {
    public static func == (lhs: ProviderRepositoryError, rhs: ProviderRepositoryError) -> Bool {
        switch (lhs, rhs) {
        case (.unimplemented, .unimplemented): return true
        default: return false
        }
    }
}

extension ClusterMetadataStoreError: Equatable {
    public static func == (lhs: ClusterMetadataStoreError, rhs: ClusterMetadataStoreError) -> Bool {
        switch (lhs, rhs) {
        case (.unimplemented, .unimplemented): return true
        default: return false
        }
    }
}

extension KeychainAccessError: Equatable {
    public static func == (lhs: KeychainAccessError, rhs: KeychainAccessError) -> Bool {
        switch (lhs, rhs) {
        case (.unimplemented, .unimplemented): return true
        default: return false
        }
    }
}

extension AuditChainError: Equatable {
    public static func == (lhs: AuditChainError, rhs: AuditChainError) -> Bool {
        switch (lhs, rhs) {
        case (.unimplemented, .unimplemented): return true
        default: return false
        }
    }
}
