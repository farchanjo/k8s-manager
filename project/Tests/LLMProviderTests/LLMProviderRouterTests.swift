// LLMProviderRouterTests.swift — llm_provider bounded context
// XCTest coverage: LLMProviderRouter routing logic using fake registry + fake adapters.

import XCTest
@testable import LLMProvider

// MARK: - LLMProviderRouterTests

final class LLMProviderRouterTests: XCTestCase {

    // MARK: - Helpers

    private func makeProfile(kind: ProviderKind, alias: String = "key-alias") -> ProviderProfile {
        ProviderProfile(
            id: UUID(),
            displayName: "Test \(kind.rawValue)",
            kind: kind,
            modelId: "test-model",
            keyAlias: alias,
            samplingDefaults: SamplingConfig(temperature: 0.7, maxOutputTokens: 1024),
            createdAtRFC3339: "2024-01-01T00:00:00Z",
            updatedAtRFC3339: "2024-01-01T00:00:00Z"
        )
    }

    private func makeRequest(profileId: UUID) -> AssistantRequest {
        AssistantRequest(
            messages: [AssistantMessage(role: .user, content: [.text(TextPart(text: "ping"))])],
            profileId: profileId
        )
    }

    // MARK: - Tests

    /// Construction smoke: router initialises without error when given valid registry and factories.
    func test_construction_smoke() {
        let registry = FakeRegistry(profiles: [makeProfile(kind: .anthropic)])
        let router = LLMProviderRouter(
            registry: registry,
            factories: [.anthropic: { _ in FakeAdapter(tag: "anthropic") as any LLMStreamingPort }]
        )
        XCTAssertNotNil(router)
    }

    /// Anthropic route: reply delegates to the Anthropic factory adapter.
    func test_anthropic_route_delegates_to_anthropic_adapter() async throws {
        let profile = makeProfile(kind: .anthropic)
        let registry = FakeRegistry(profiles: [profile])
        let router = LLMProviderRouter(
            registry: registry,
            factories: [.anthropic: { _ in FakeAdapter(tag: "anthropic") as any LLMStreamingPort }]
        )

        let request = makeRequest(profileId: profile.id)
        var events: [AssistantStreamEvent] = []
        for try await event in router.reply(to: request) {
            events.append(event)
        }

        guard case .delta(let d) = events.first else {
            return XCTFail("Expected .delta as first event, got \(events)")
        }
        XCTAssertEqual(d.text, "anthropic")
    }

    /// OpenAI route: reply delegates to the OpenAI factory adapter.
    func test_openai_route_delegates_to_openai_adapter() async throws {
        let profile = makeProfile(kind: .openai)
        let registry = FakeRegistry(profiles: [profile])
        let router = LLMProviderRouter(
            registry: registry,
            factories: [.openai: { _ in FakeAdapter(tag: "openai") as any LLMStreamingPort }]
        )

        let request = makeRequest(profileId: profile.id)
        var events: [AssistantStreamEvent] = []
        for try await event in router.reply(to: request) {
            events.append(event)
        }

        guard case .delta(let d) = events.first else {
            return XCTFail("Expected .delta as first event, got \(events)")
        }
        XCTAssertEqual(d.text, "openai")
    }

    /// Missing profile: reply throws `RouterError.profileNotFound` for an unknown `profileId`.
    func test_missing_profile_throws_routing_error() async throws {
        let registry = FakeRegistry(profiles: [])
        let router = LLMProviderRouter(
            registry: registry,
            factories: [.anthropic: { _ in FakeAdapter(tag: "x") as any LLMStreamingPort }]
        )

        let unknownId = UUID()
        let request = makeRequest(profileId: unknownId)
        var caughtProfileNotFound = false
        do {
            for try await _ in router.reply(to: request) {}
        } catch RouterError.profileNotFound(let id) {
            caughtProfileNotFound = true
            XCTAssertEqual(id, unknownId)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(caughtProfileNotFound, "Expected RouterError.profileNotFound")
    }

    /// Factory error propagation: when the factory throws, the error surfaces from the stream.
    func test_factory_error_propagates() async throws {
        let profile = makeProfile(kind: .anthropic)
        let registry = FakeRegistry(profiles: [profile])
        let router = LLMProviderRouter(
            registry: registry,
            factories: [
                .anthropic: { _ -> any LLMStreamingPort in throw FactoryError.boom },
            ]
        )

        let request = makeRequest(profileId: profile.id)
        var caughtFactoryFailed = false
        do {
            for try await _ in router.reply(to: request) {}
        } catch RouterError.factoryFailed(let kind, _) {
            caughtFactoryFailed = true
            XCTAssertEqual(kind, .anthropic)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(caughtFactoryFailed, "Expected RouterError.factoryFailed")
    }
}

// MARK: - Test doubles

/// Fake registry backed by an in-memory profile array.
private struct FakeRegistry: LLMProviderRegistryPort {
    let profiles: [ProviderProfile]

    func allProfiles() async throws -> [ProviderProfile] { profiles }

    func profile(id: UUID) async throws -> ProviderProfile {
        guard let p = profiles.first(where: { $0.id == id }) else {
            throw LLMRegistryError.notFound(id)
        }
        return p
    }

    func upsert(_ profile: ProviderProfile) async throws {}
    func delete(id: UUID) async throws {}

    func listReadModel() async throws -> ProviderListReadModel {
        ProviderListReadModel(rows: [])
    }

    func capabilityReadModel(profileId: UUID) async throws -> ProviderCapabilityReadModel? { nil }
    func upsertCapability(_ model: ProviderCapabilityReadModel) async throws {}
}

/// Fake adapter that emits a single `.delta` event containing `tag`, then `.finish`.
private struct FakeAdapter: LLMStreamingPort {
    let tag: String

    func reply(to request: AssistantRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        let captured = tag
        return AsyncThrowingStream { continuation in
            continuation.yield(.delta(DeltaEvent(text: captured)))
            continuation.yield(.finish(FinishEvent(reason: .stop)))
            continuation.finish()
        }
    }
}

/// Sentinel error thrown by the factory in the propagation test.
private enum FactoryError: Error {
    case boom
}
