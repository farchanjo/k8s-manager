// Tests/LLMProviderTests/ProviderProfileEndpointValidationTests.swift
// Tests: ProviderProfile.validateEndpoint() — ADR-0045.

import Testing
import Foundation
import LLMProvider

// MARK: - Helpers

private func makeProfile(
    baseURL: URL?,
    localOnly: Bool = false
) -> ProviderProfile {
    ProviderProfile(
        id: UUID(),
        displayName: "Test",
        kind: .openaiCompatible,
        baseURL: baseURL,
        modelId: "test-model",
        keyAlias: "test-key",
        samplingDefaults: SamplingConfig(temperature: 0.7, maxOutputTokens: 1024),
        createdAtRFC3339: "2026-01-01T00:00:00Z",
        updatedAtRFC3339: "2026-01-01T00:00:00Z",
        localOnly: localOnly
    )
}

// MARK: - ProviderProfileEndpointValidationTests

@Suite("ProviderProfile endpoint validation — ADR-0045")
struct ProviderProfileEndpointValidationTests {

    // MARK: Non-openaiCompatible profiles (exempt)

    @Test("Anthropic profile with no baseURL passes without error")
    func anthropicProfileExempt() throws {
        let profile = ProviderProfile(
            id: UUID(),
            displayName: "Anthropic",
            kind: .anthropic,
            baseURL: nil,
            modelId: "claude-sonnet-4-6",
            keyAlias: "anthropic-key",
            samplingDefaults: SamplingConfig(temperature: 0.7, maxOutputTokens: 2048),
            createdAtRFC3339: "2026-01-01T00:00:00Z",
            updatedAtRFC3339: "2026-01-01T00:00:00Z"
        )
        #expect(throws: Never.self) { try profile.validateEndpoint() }
    }

    // MARK: localOnly == true — accepted

    @Test("localOnly profile with localhost:11434 is accepted")
    func localOnlyLocalhostAccepted() throws {
        let profile = makeProfile(
            baseURL: URL(string: "http://localhost:11434"),
            localOnly: true
        )
        #expect(throws: Never.self) { try profile.validateEndpoint() }
    }

    @Test("localOnly profile with 127.0.0.1:8080 is accepted")
    func localOnly127Accepted() throws {
        let profile = makeProfile(
            baseURL: URL(string: "http://127.0.0.1:8080"),
            localOnly: true
        )
        #expect(throws: Never.self) { try profile.validateEndpoint() }
    }

    // MARK: localOnly == true — rejected

    @Test("localOnly profile pointing to remote host is rejected")
    func localOnlyRemoteRejected() throws {
        let profile = makeProfile(
            baseURL: URL(string: "http://192.168.1.50:11434"),
            localOnly: true
        )
        #expect(throws: EndpointValidationError.self) { try profile.validateEndpoint() }
    }

    // MARK: localOnly == false — private networks rejected

    @Test("10.x.x.x private address rejected when localOnly==false")
    func privateClassARejectsed() throws {
        let profile = makeProfile(baseURL: URL(string: "http://10.0.0.1:8080"))
        #expect(throws: EndpointValidationError.self) { try profile.validateEndpoint() }
    }

    @Test("192.168.x.x private address rejected")
    func privateClassCRejected() throws {
        let profile = makeProfile(baseURL: URL(string: "http://192.168.1.1:8080"))
        #expect(throws: EndpointValidationError.self) { try profile.validateEndpoint() }
    }

    @Test("172.16.x.x private address rejected")
    func privateClassBRejected() throws {
        let profile = makeProfile(baseURL: URL(string: "http://172.16.0.1:8080"))
        #expect(throws: EndpointValidationError.self) { try profile.validateEndpoint() }
    }

    @Test("127.0.0.1 loopback rejected when localOnly==false")
    func loopbackRejectedWhenNotLocalOnly() throws {
        let profile = makeProfile(baseURL: URL(string: "http://127.0.0.1:8080"))
        #expect(throws: EndpointValidationError.self) { try profile.validateEndpoint() }
    }

    @Test("IPv4 link-local 169.254.x.x rejected")
    func ipv4LinkLocalRejected() throws {
        let profile = makeProfile(baseURL: URL(string: "http://169.254.1.1:8080"))
        #expect(throws: EndpointValidationError.self) { try profile.validateEndpoint() }
    }

    @Test(".local mDNS suffix rejected")
    func mdnsSuffixRejected() throws {
        let profile = makeProfile(baseURL: URL(string: "http://ollama.local:11434"))
        #expect(throws: EndpointValidationError.self) { try profile.validateEndpoint() }
    }

    // MARK: Public endpoint accepted

    @Test("Public routable endpoint passes validation")
    func publicEndpointAccepted() throws {
        let profile = makeProfile(baseURL: URL(string: "https://api.ollama.example.com:443"))
        #expect(throws: Never.self) { try profile.validateEndpoint() }
    }
}
