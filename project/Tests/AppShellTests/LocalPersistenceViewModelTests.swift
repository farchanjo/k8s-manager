// Tests/AppShellTests/LocalPersistenceViewModelTests.swift
// Coverage: LocalPersistenceViewModel — store info, audit chain, keychain loads.

import XCTest
import Dependencies
@testable import AppShell
import LocalPersistence

// MARK: - LocalPersistenceViewModelTests

@MainActor
final class LocalPersistenceViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_allResourcesAreIdle() {
        let sut = LocalPersistenceViewModel()
        XCTAssertTrue(sut.store.isIdle)
        XCTAssertTrue(sut.auditChainState.isIdle)
        XCTAssertTrue(sut.keychainEntries.isIdle)
    }

    // MARK: loadAuditChainState

    func test_loadAuditChainState_setsSuccessOnIntactChain() async {
        let fakeAudit = FakeAuditChainPort(state: .intact)

        await withDependencies {
            $0.auditChain = fakeAudit
        } operation: {
            let sut = LocalPersistenceViewModel()
            await sut.loadAuditChainState()
            XCTAssertEqual(sut.auditChainState.value, .intact)
        }
    }

    func test_loadAuditChainState_setsFailureOnError() async {
        let fakeAudit = FakeAuditChainPort(error: AuditChainError.keychainLocked)

        await withDependencies {
            $0.auditChain = fakeAudit
        } operation: {
            let sut = LocalPersistenceViewModel()
            await sut.loadAuditChainState()
            XCTAssertNotNil(sut.auditChainState.error)
            XCTAssertNil(sut.auditChainState.value)
        }
    }

    // MARK: loadKeychainEntries

    func test_loadKeychainEntries_accumulatesAllNamespaces() async {
        let llmEntry = KeychainEntry(
            namespace: .llm, account: "anthropic-key",
            label: "K8sManager LLM key", maxPayloadBytes: 256
        )
        let auditEntry = KeychainEntry(
            namespace: .audit, account: "chain-mac-key-v1",
            label: "K8sManager audit chain MAC key - v1", maxPayloadBytes: 32
        )
        let fakeKeychain = FakeKeychainAccessPort(entriesByNamespace: [
            .llm: [llmEntry],
            .audit: [auditEntry],
            .oidc: [],
            .azure: [],
        ])
        let fakeAudit = FakeAuditChainPort(state: .intact)

        await withDependencies {
            $0.keychainAccess = fakeKeychain
            $0.auditChain = fakeAudit
        } operation: {
            let sut = LocalPersistenceViewModel()
            await sut.loadKeychainEntries()
            let entries = sut.keychainEntries.value
            XCTAssertEqual(entries?.count, 2)
        }
    }

    func test_loadKeychainEntries_setsFailureOnPortError() async {
        let fakeKeychain = FakeKeychainAccessPort(
            error: KeychainAccessError.keychainLocked
        )
        let fakeAudit = FakeAuditChainPort(state: .intact)

        await withDependencies {
            $0.keychainAccess = fakeKeychain
            $0.auditChain = fakeAudit
        } operation: {
            let sut = LocalPersistenceViewModel()
            await sut.loadKeychainEntries()
            XCTAssertNotNil(sut.keychainEntries.error)
        }
    }

    // MARK: loadStoreInfo

    func test_loadStoreInfo_setsSuccessWhenAuditChainResponds() async {
        let fakeAudit = FakeAuditChainPort(state: .intact)

        await withDependencies {
            $0.auditChain = fakeAudit
        } operation: {
            let sut = LocalPersistenceViewModel()
            await sut.loadStoreInfo()
            let storeValue = sut.store.value
            XCTAssertNotNil(storeValue)
            XCTAssertEqual(storeValue?.journalMode, "wal")
            XCTAssertGreaterThanOrEqual(storeValue?.schemaVersion ?? 0, 1)
        }
    }
}

// MARK: - Test doubles

private struct FakeAuditChainPort: AuditChainPort {
    let stubbedState: AuditChainState?
    let stubbedError: Error?

    init(state: AuditChainState? = nil, error: Error? = nil) {
        self.stubbedState = state
        self.stubbedError = error
    }

    func append(entry: AuditEntry) async throws {
        throw AuditChainError.unimplemented
    }

    func verifyPrecedingEntry(before entry: AuditEntry) async throws -> Bool {
        throw AuditChainError.unimplemented
    }

    func verifyFullChain() async throws -> AuditChainState {
        if let error = stubbedError { throw error }
        return stubbedState!
    }

    func currentState() async throws -> AuditChainState {
        if let error = stubbedError { throw error }
        return stubbedState!
    }
}

private struct FakeKeychainAccessPort: KeychainAccessPort {
    let stubbedEntries: [KeychainServiceNamespace: [KeychainEntry]]
    let stubbedError: Error?

    init(
        entriesByNamespace: [KeychainServiceNamespace: [KeychainEntry]] = [:],
        error: Error? = nil
    ) {
        self.stubbedEntries = entriesByNamespace
        self.stubbedError = error
    }

    func readSecret(for entry: KeychainEntry) async throws -> Data {
        throw KeychainAccessError.unimplemented
    }

    func writeSecret(_ secret: Data, for entry: KeychainEntry) async throws {
        throw KeychainAccessError.unimplemented
    }

    func deleteSecret(for entry: KeychainEntry) async throws {
        throw KeychainAccessError.unimplemented
    }

    func listEntries(namespace: KeychainServiceNamespace) async throws -> [KeychainEntry] {
        if let error = stubbedError { throw error }
        return stubbedEntries[namespace] ?? []
    }
}
