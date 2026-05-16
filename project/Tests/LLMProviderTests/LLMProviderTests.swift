// LLMProviderTests.swift — llm_provider bounded context
// XCTest coverage: domain types, stream event model, DI port overrides.

import XCTest
import Dependencies
@testable import LLMProvider

// MARK: - ProviderProfileTests

final class ProviderProfileTests: XCTestCase {
    func test_providerProfile_construction_roundtrips_fields() {
        let id = UUID()
        let sampling = SamplingConfig(
            temperature: 0.7,
            topP: 0.9,
            maxOutputTokens: 4096,
            stopSequences: ["</s>"],
            providerHints: ["anthropic_prompt_caching": "ephemeral"]
        )
        let profile = ProviderProfile(
            id: id,
            displayName: "Claude Sonnet",
            kind: .anthropic,
            baseURL: nil,
            modelId: "claude-sonnet-4-6",
            keyAlias: "anthropic-key-prod",
            samplingDefaults: sampling,
            createdAtRFC3339: "2024-01-01T00:00:00Z",
            updatedAtRFC3339: "2024-06-01T00:00:00Z"
        )

        XCTAssertEqual(profile.id, id)
        XCTAssertEqual(profile.displayName, "Claude Sonnet")
        XCTAssertEqual(profile.kind, .anthropic)
        XCTAssertNil(profile.baseURL)
        XCTAssertEqual(profile.modelId, "claude-sonnet-4-6")
        XCTAssertEqual(profile.keyAlias, "anthropic-key-prod")
        XCTAssertEqual(profile.samplingDefaults.temperature, 0.7)
        XCTAssertEqual(profile.samplingDefaults.stopSequences, ["</s>"])
    }

    func test_openaiCompatible_profile_stores_baseURL() {
        let base = URL(string: "https://ollama.local:11434/v1")!
        let profile = ProviderProfile(
            id: UUID(),
            displayName: "Qwen3 local",
            kind: .openaiCompatible,
            baseURL: base,
            modelId: "qwen3:32b-instruct",
            keyAlias: "ollama-no-key",
            samplingDefaults: SamplingConfig(temperature: 0.0, maxOutputTokens: 8192),
            createdAtRFC3339: "2024-01-01T00:00:00Z",
            updatedAtRFC3339: "2024-01-01T00:00:00Z"
        )

        XCTAssertEqual(profile.baseURL, base)
        XCTAssertEqual(profile.kind, .openaiCompatible)
    }

    func test_samplingConfig_defaults_empty_collections() {
        let cfg = SamplingConfig(temperature: 1.0, maxOutputTokens: 2048)

        XCTAssertTrue(cfg.stopSequences.isEmpty)
        XCTAssertTrue(cfg.providerHints.isEmpty)
        XCTAssertNil(cfg.topP)
        XCTAssertNil(cfg.topK)
    }

    func test_providerKind_allCases_covered() {
        let all = ProviderKind.allCases
        XCTAssertTrue(all.contains(.anthropic))
        XCTAssertTrue(all.contains(.openai))
        XCTAssertTrue(all.contains(.openaiCompatible))
    }
}

// MARK: - AssistantMessageTests

final class AssistantMessageTests: XCTestCase {
    func test_textPart_construction() {
        let part = TextPart(text: "Hello", cacheControl: .ephemeral)
        XCTAssertEqual(part.text, "Hello")
        XCTAssertEqual(part.cacheControl, .ephemeral)
    }

    func test_toolUsePart_construction() {
        let part = ToolUsePart(
            callId: "call_abc123",
            name: "list_pods",
            jsonArguments: #"{"namespace":"default"}"#
        )
        XCTAssertEqual(part.callId, "call_abc123")
        XCTAssertEqual(part.name, "list_pods")
    }

    func test_toolResultPart_error_flag() {
        let ok = ToolResultPart(callId: "x", jsonResult: #"{"pods":[]}"#, isError: false)
        let err = ToolResultPart(callId: "x", jsonResult: #"{"error":"timeout"}"#, isError: true)
        XCTAssertFalse(ok.isError)
        XCTAssertTrue(err.isError)
    }

    func test_assistantMessage_role_and_content() {
        let msg = AssistantMessage(
            role: .user,
            content: [.text(TextPart(text: "What is the cluster status?"))]
        )
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content.count, 1)
    }

    func test_toolDefinition_fields() {
        let def = ToolDefinition(
            name: "get_logs",
            description: "Fetches pod logs",
            inputJSONSchema: #"{"type":"object"}"#
        )
        XCTAssertEqual(def.name, "get_logs")
        XCTAssertFalse(def.description.isEmpty)
    }
}

// MARK: - AssistantStreamEventTests

final class AssistantStreamEventTests: XCTestCase {
    func test_deltaEvent_text() {
        let event = AssistantStreamEvent.delta(DeltaEvent(text: "Hello, "))
        guard case .delta(let d) = event else {
            return XCTFail("Expected .delta")
        }
        XCTAssertEqual(d.text, "Hello, ")
    }

    func test_toolUseStart_fields() {
        let event = AssistantStreamEvent.toolUseStart(
            ToolUseStartEvent(callId: "call_1", name: "list_pods")
        )
        guard case .toolUseStart(let e) = event else {
            return XCTFail("Expected .toolUseStart")
        }
        XCTAssertEqual(e.callId, "call_1")
        XCTAssertEqual(e.name, "list_pods")
    }

    func test_toolUseDelta_jsonChunk() {
        let event = AssistantStreamEvent.toolUseDelta(
            ToolUseDeltaEvent(callId: "call_1", jsonChunk: #"{"name"#)
        )
        guard case .toolUseDelta(let e) = event else {
            return XCTFail("Expected .toolUseDelta")
        }
        XCTAssertEqual(e.jsonChunk, #"{"name"#)
    }

    func test_toolUseFinish_totalArguments() {
        let event = AssistantStreamEvent.toolUseFinish(
            ToolUseFinishEvent(callId: "call_1", totalArguments: #"{"namespace":"kube-system"}"#)
        )
        guard case .toolUseFinish(let e) = event else {
            return XCTFail("Expected .toolUseFinish")
        }
        XCTAssertEqual(e.totalArguments, #"{"namespace":"kube-system"}"#)
    }

    func test_usageEvent_fields() {
        let event = AssistantStreamEvent.usage(
            UsageEvent(promptTokens: 100, completionTokens: 50, cachedPromptTokens: 80)
        )
        guard case .usage(let u) = event else {
            return XCTFail("Expected .usage")
        }
        XCTAssertEqual(u.promptTokens, 100)
        XCTAssertEqual(u.completionTokens, 50)
        XCTAssertEqual(u.cachedPromptTokens, 80)
    }

    func test_finishEvent_stop_reason() {
        let event = AssistantStreamEvent.finish(FinishEvent(reason: .stop))
        guard case .finish(let f) = event else {
            return XCTFail("Expected .finish")
        }
        XCTAssertEqual(f.reason, .stop)
        XCTAssertNil(f.detail)
    }

    func test_finishEvent_error_carries_detail() {
        let event = AssistantStreamEvent.finish(
            FinishEvent(reason: .error, detail: "rate_limit_exceeded")
        )
        guard case .finish(let f) = event else {
            return XCTFail("Expected .finish")
        }
        XCTAssertEqual(f.reason, .error)
        XCTAssertEqual(f.detail, "rate_limit_exceeded")
    }
}

// MARK: - LLMStreamingPortDITests

final class LLMStreamingPortDITests: XCTestCase {
    func test_portCanBeOverridden_viaDependencies() async throws {
        let fake = FakeLLMStreamingPort(events: [
            .delta(DeltaEvent(text: "Hi")),
            .finish(FinishEvent(reason: .stop)),
        ])

        try await withDependencies {
            $0.llmStreaming = fake
        } operation: {
            @Dependency(\.llmStreaming) var port
            let request = AssistantRequest(
                messages: [AssistantMessage(
                    role: .user,
                    content: [.text(TextPart(text: "Hello"))]
                )],
                profileId: UUID()
            )
            var collected: [AssistantStreamEvent] = []
            for try await event in port.reply(to: request) {
                collected.append(event)
            }
            XCTAssertEqual(collected.count, 2)
            guard case .delta(let d) = collected[0] else {
                return XCTFail("Expected .delta first")
            }
            XCTAssertEqual(d.text, "Hi")
        }
    }

    func test_unimplementedPort_throws_on_reply() async {
        let port = UnimplementedLLMStreamingPort()
        let request = AssistantRequest(
            messages: [],
            profileId: UUID()
        )
        var threwUnimplemented = false
        do {
            for try await _ in port.reply(to: request) {}
        } catch LLMStreamingError.unimplemented {
            threwUnimplemented = true
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(threwUnimplemented)
    }
}

// MARK: - LLMKeyStorePortDITests

final class LLMKeyStorePortDITests: XCTestCase {
    func test_keyStoreCanBeOverridden_viaDependencies() async throws {
        let fake = FakeLLMKeyStorePort(secrets: ["my-alias": "sk-test-1234"])

        try await withDependencies {
            $0.llmKeyStore = fake
        } operation: {
            @Dependency(\.llmKeyStore) var store
            let secret = try await store.secret(for: "my-alias")
            XCTAssertEqual(secret, "sk-test-1234")
        }
    }

    func test_unimplementedKeyStore_throws() async {
        let store = UnimplementedLLMKeyStorePort()
        do {
            _ = try await store.secret(for: "any")
            XCTFail("Expected throw")
        } catch LLMKeyStoreError.unimplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - LLMProviderRegistryPortDITests

final class LLMProviderRegistryPortDITests: XCTestCase {
    func test_registryCanBeOverridden_viaDependencies() async throws {
        let profile = ProviderProfile(
            id: UUID(),
            displayName: "Test",
            kind: .openai,
            modelId: "gpt-5.3",
            keyAlias: "openai-key",
            samplingDefaults: SamplingConfig(temperature: 0.5, maxOutputTokens: 1024),
            createdAtRFC3339: "2024-01-01T00:00:00Z",
            updatedAtRFC3339: "2024-01-01T00:00:00Z"
        )
        let fake = FakeLLMProviderRegistry(profiles: [profile])

        try await withDependencies {
            $0.llmProviderRegistry = fake
        } operation: {
            @Dependency(\.llmProviderRegistry) var registry
            let all = try await registry.allProfiles()
            XCTAssertEqual(all.count, 1)
            XCTAssertEqual(all[0].displayName, "Test")
        }
    }

    func test_unimplementedRegistry_throws() async {
        let registry = UnimplementedLLMProviderRegistryPort()
        do {
            _ = try await registry.allProfiles()
            XCTFail("Expected throw")
        } catch LLMRegistryError.unimplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Test doubles

private struct FakeLLMStreamingPort: LLMStreamingPort {
    let events: [AssistantStreamEvent]

    func reply(to request: AssistantRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        let captured = events
        return AsyncThrowingStream { continuation in
            for event in captured {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private struct FakeLLMKeyStorePort: LLMKeyStorePort {
    var secrets: [String: String]

    func secret(for alias: String) async throws -> String {
        guard let value = secrets[alias] else {
            throw LLMKeyStoreError.notFound(alias: alias)
        }
        return value
    }

    func store(secret: String, for alias: String) async throws {}
    func delete(alias: String) async throws {}
}

private struct FakeLLMProviderRegistry: LLMProviderRegistryPort {
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
        ProviderListReadModel(rows: profiles.map {
            ProviderListReadModel.Row(
                id: $0.id,
                displayName: $0.displayName,
                kind: $0.kind,
                modelId: $0.modelId
            )
        })
    }

    func capabilityReadModel(profileId: UUID) async throws -> ProviderCapabilityReadModel? { nil }

    func upsertCapability(_ model: ProviderCapabilityReadModel) async throws {}
}
