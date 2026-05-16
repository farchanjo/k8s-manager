// Ports/Dependencies.swift — llm_provider bounded context
// DI registry via pointfreeco/swift-dependencies
// ADR ref: ADR-0020 (dependency injection strategy)

import Dependencies
import Foundation

// MARK: - LLMStreamingPortKey

/// `DependencyKey` for `LLMStreamingPort`.
///
/// `liveValue` and `testValue` are both the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. Adapter targets override `liveValue`
/// at the composition root.
public enum LLMStreamingPortKey: DependencyKey {
    public static let liveValue: any LLMStreamingPort = UnimplementedLLMStreamingPort()
    public static let testValue: any LLMStreamingPort = UnimplementedLLMStreamingPort()
}

public extension DependencyValues {
    /// The port that streams normalised completions from a provider adapter.
    var llmStreaming: any LLMStreamingPort {
        get { self[LLMStreamingPortKey.self] }
        set { self[LLMStreamingPortKey.self] = newValue }
    }
}

// MARK: - LLMKeyStorePortKey

/// `DependencyKey` for `LLMKeyStorePort`.
public enum LLMKeyStorePortKey: DependencyKey {
    public static let liveValue: any LLMKeyStorePort = UnimplementedLLMKeyStorePort()
    public static let testValue: any LLMKeyStorePort = UnimplementedLLMKeyStorePort()
}

public extension DependencyValues {
    /// The port that reads provider API keys from the system Keychain.
    var llmKeyStore: any LLMKeyStorePort {
        get { self[LLMKeyStorePortKey.self] }
        set { self[LLMKeyStorePortKey.self] = newValue }
    }
}

// MARK: - LLMProviderRegistryPortKey

/// `DependencyKey` for `LLMProviderRegistryPort`.
public enum LLMProviderRegistryPortKey: DependencyKey {
    public static let liveValue: any LLMProviderRegistryPort = UnimplementedLLMProviderRegistryPort()
    public static let testValue: any LLMProviderRegistryPort = UnimplementedLLMProviderRegistryPort()
}

public extension DependencyValues {
    /// The port that persists and queries `ProviderProfile` aggregates.
    var llmProviderRegistry: any LLMProviderRegistryPort {
        get { self[LLMProviderRegistryPortKey.self] }
        set { self[LLMProviderRegistryPortKey.self] = newValue }
    }
}
