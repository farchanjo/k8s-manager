// Tests/AppShellTests/LLMProviderViewModelTests.swift
// Coverage: LLMProviderViewModel load + select + error flows.

import XCTest
import Dependencies
@testable import AppShell
import LLMProvider

// MARK: - LLMProviderViewModelTests

@MainActor
final class LLMProviderViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = LLMProviderViewModel()
        XCTAssertTrue(sut.providers.isIdle)
        XCTAssertNil(sut.selectedProviderId)
    }

    // MARK: loadProviders — success

    func test_loadProviders_setsProvidersOnSuccess() async {
        let rows = [
            makeRow(name: "Anthropic Production", kind: .anthropic),
            makeRow(name: "OpenAI Staging", kind: .openai),
        ]
        let model = ProviderListReadModel(rows: rows)
        let fakeRegistry = FakeLLMProviderRegistry(model: model)

        await withDependencies {
            $0.llmProviderRegistry = fakeRegistry
        } operation: {
            let sut = LLMProviderViewModel()
            await sut.loadProviders()
            XCTAssertEqual(sut.providers.value?.rows.count, 2)
            XCTAssertNil(sut.providers.error)
        }
    }

    // MARK: loadProviders — failure

    func test_loadProviders_setsFailureOnRegistryError() async {
        let fakeRegistry = FakeLLMProviderRegistry(error: LLMRegistryError.unimplemented)

        await withDependencies {
            $0.llmProviderRegistry = fakeRegistry
        } operation: {
            let sut = LLMProviderViewModel()
            await sut.loadProviders()
            XCTAssertNotNil(sut.providers.error)
            XCTAssertNil(sut.providers.value)
        }
    }

    // MARK: selectProvider

    func test_selectProvider_updatesSelectedProviderId() async {
        let row = makeRow(name: "Local Ollama", kind: .openaiCompatible)
        let model = ProviderListReadModel(rows: [row])
        let fakeRegistry = FakeLLMProviderRegistry(model: model)

        await withDependencies {
            $0.llmProviderRegistry = fakeRegistry
        } operation: {
            let sut = LLMProviderViewModel()
            await sut.loadProviders()
            sut.selectProvider(row)
            XCTAssertEqual(sut.selectedProviderId, row.id)
        }
    }

    // MARK: loadProviders — empty list

    func test_loadProviders_succeedsWithEmptyList() async {
        let fakeRegistry = FakeLLMProviderRegistry(model: ProviderListReadModel(rows: []))

        await withDependencies {
            $0.llmProviderRegistry = fakeRegistry
        } operation: {
            let sut = LLMProviderViewModel()
            await sut.loadProviders()
            XCTAssertEqual(sut.providers.value?.rows.count, 0)
        }
    }

    // MARK: loadProviders — retry after failure

    func test_loadProviders_recoversOnRetry() async {
        let rows = [makeRow(name: "Claude", kind: .anthropic)]
        let fakeRegistry = FakeLLMProviderRegistry(
            model: ProviderListReadModel(rows: rows),
            error: nil,
            failFirstCall: true
        )

        await withDependencies {
            $0.llmProviderRegistry = fakeRegistry
        } operation: {
            let sut = LLMProviderViewModel()
            await sut.loadProviders()
            XCTAssertNotNil(sut.providers.error, "first call should fail")
            await sut.loadProviders()
            XCTAssertEqual(sut.providers.value?.rows.count, 1, "retry should succeed")
        }
    }
}

// MARK: - Helpers

private func makeRow(
    name: String,
    kind: ProviderKind,
    verified: Bool = false
) -> ProviderListReadModel.Row {
    ProviderListReadModel.Row(
        id: UUID(),
        displayName: name,
        kind: kind,
        modelId: "test-model",
        lastVerifiedAtRFC3339: verified ? "2026-01-01T00:00:00Z" : nil
    )
}

// MARK: - Test doubles

private final class FakeLLMProviderRegistry: LLMProviderRegistryPort, @unchecked Sendable {
    private let stubbedModel: ProviderListReadModel
    private let stubbedError: Error?
    private let failFirstCall: Bool
    private var callCount = 0

    init(
        model: ProviderListReadModel = ProviderListReadModel(rows: []),
        error: Error? = nil,
        failFirstCall: Bool = false
    ) {
        self.stubbedModel = model
        self.stubbedError = error
        self.failFirstCall = failFirstCall
    }

    func listReadModel() async throws -> ProviderListReadModel {
        callCount += 1
        if failFirstCall && callCount == 1 {
            throw LLMRegistryError.storageError(detail: "first-call failure")
        }
        if let error = stubbedError { throw error }
        return stubbedModel
    }

    func allProfiles() async throws -> [ProviderProfile] { throw LLMRegistryError.unimplemented }
    func profile(id: UUID) async throws -> ProviderProfile { throw LLMRegistryError.unimplemented }
    func upsert(_ profile: ProviderProfile) async throws { throw LLMRegistryError.unimplemented }
    func delete(id: UUID) async throws { throw LLMRegistryError.unimplemented }
    func capabilityReadModel(profileId: UUID) async throws -> ProviderCapabilityReadModel? { nil }
    func upsertCapability(_ model: ProviderCapabilityReadModel) async throws {
        throw LLMRegistryError.unimplemented
    }
}
