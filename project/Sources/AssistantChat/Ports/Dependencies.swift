// Ports/Dependencies.swift — assistant_chat bounded context
// DI registry via pointfreeco/swift-dependencies
// ADR ref: ADR-0020 (dependency injection strategy)

import Dependencies
import SharedKernel

// MARK: - ChatRepositoryPortKey

/// `DependencyKey` for `ChatRepositoryPort`.
///
/// `liveValue` and `testValue` are both the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. Adapter targets override `liveValue`
/// at composition root.
public enum ChatRepositoryPortKey: DependencyKey {
    public static let liveValue: any ChatRepositoryPort = UnimplementedChatRepositoryPort()
    public static let testValue: any ChatRepositoryPort = UnimplementedChatRepositoryPort()
}

public extension DependencyValues {
    /// The port responsible for persisting sessions, messages, and tool-call
    /// records.
    var chatRepository: any ChatRepositoryPort {
        get { self[ChatRepositoryPortKey.self] }
        set { self[ChatRepositoryPortKey.self] = newValue }
    }
}

// MARK: - PromptInjectionFilterPortKey

/// `DependencyKey` for `PromptInjectionFilterPort`.
///
/// `liveValue` is the concrete `ContentFilterGateway` actor (ADR-0048, Layer 3).
public enum PromptInjectionFilterPortKey: DependencyKey {
    public static let liveValue: any PromptInjectionFilterPort = ContentFilterGateway()
    public static let testValue: any PromptInjectionFilterPort = UnimplementedPromptInjectionFilterPort()
}

public extension DependencyValues {
    /// The port that evaluates cluster-origin strings against the Layer-3
    /// prompt injection Rego policy (ADR-0048).
    var promptInjectionFilter: any PromptInjectionFilterPort {
        get { self[PromptInjectionFilterPortKey.self] }
        set { self[PromptInjectionFilterPortKey.self] = newValue }
    }
}

// MARK: - ToolDispatcherPortKey

/// `DependencyKey` for `ToolDispatcherPort`.
public enum ToolDispatcherPortKey: DependencyKey {
    public static let liveValue: any ToolDispatcherPort = UnimplementedToolDispatcherPort()
    public static let testValue: any ToolDispatcherPort = UnimplementedToolDispatcherPort()
}

public extension DependencyValues {
    /// The port that bridges LLM tool-use events to the in-process MCP server
    /// (ADR-0009).
    var toolDispatcher: any ToolDispatcherPort {
        get { self[ToolDispatcherPortKey.self] }
        set { self[ToolDispatcherPortKey.self] = newValue }
    }
}

// MARK: - ToolCallRateLimiterKey

/// `DependencyKey` for `ToolCallRateLimiter`.
///
/// Both `liveValue` and `testValue` are a permissive shared instance that
/// always admits calls, so unit tests that do not exercise rate-limiting
/// behaviour compile and run without additional setup.
public enum ToolCallRateLimiterKey: DependencyKey {
    public static let liveValue: ToolCallRateLimiter = ToolCallRateLimiter()
    public static let testValue: ToolCallRateLimiter = ToolCallRateLimiter()
}

public extension DependencyValues {
    /// Per-session sliding-window rate limiter for assistant tool calls
    /// (ADR-0043).
    var toolCallRateLimiter: ToolCallRateLimiter {
        get { self[ToolCallRateLimiterKey.self] }
        set { self[ToolCallRateLimiterKey.self] = newValue }
    }
}
