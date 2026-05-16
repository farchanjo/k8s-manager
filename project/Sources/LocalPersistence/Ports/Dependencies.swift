// Ports/Dependencies.swift — local_persistence bounded context
// DI registry via pointfreeco/swift-dependencies (ADR-0020)
//
// Each port gets a `DependencyKey` whose `liveValue` and `testValue` are both
// the matching `Unimplemented*Port` sentinel. Adapter targets override
// `liveValue` at the composition root.

import Dependencies

// MARK: - ChatRepositoryPortKey

/// `DependencyKey` for `ChatRepositoryPort`.
public enum ChatRepositoryPortKey: DependencyKey {
    public static let liveValue: any ChatRepositoryPort = UnimplementedChatRepositoryPort()
    public static let testValue: any ChatRepositoryPort = UnimplementedChatRepositoryPort()
}

public extension DependencyValues {
    /// The port for reading and writing chat sessions and messages.
    var chatRepository: any ChatRepositoryPort {
        get { self[ChatRepositoryPortKey.self] }
        set { self[ChatRepositoryPortKey.self] = newValue }
    }
}

// MARK: - ProviderRepositoryPortKey

/// `DependencyKey` for `ProviderRepositoryPort`.
public enum ProviderRepositoryPortKey: DependencyKey {
    public static let liveValue: any ProviderRepositoryPort = UnimplementedProviderRepositoryPort()
    public static let testValue: any ProviderRepositoryPort = UnimplementedProviderRepositoryPort()
}

public extension DependencyValues {
    /// The port for reading and writing LLM provider profiles.
    var providerRepository: any ProviderRepositoryPort {
        get { self[ProviderRepositoryPortKey.self] }
        set { self[ProviderRepositoryPortKey.self] = newValue }
    }
}

// MARK: - ClusterMetadataStorePortKey

/// `DependencyKey` for `ClusterMetadataStorePort`.
public enum ClusterMetadataStorePortKey: DependencyKey {
    public static let liveValue: any ClusterMetadataStorePort = UnimplementedClusterMetadataStorePort()
    public static let testValue: any ClusterMetadataStorePort = UnimplementedClusterMetadataStorePort()
}

public extension DependencyValues {
    /// The port for reading and writing the cluster-analysis TTL cache.
    var clusterMetadataStore: any ClusterMetadataStorePort {
        get { self[ClusterMetadataStorePortKey.self] }
        set { self[ClusterMetadataStorePortKey.self] = newValue }
    }
}

// MARK: - KeychainAccessPortKey

/// `DependencyKey` for `KeychainAccessPort`.
public enum KeychainAccessPortKey: DependencyKey {
    public static let liveValue: any KeychainAccessPort = UnimplementedKeychainAccessPort()
    public static let testValue: any KeychainAccessPort = UnimplementedKeychainAccessPort()
}

public extension DependencyValues {
    /// The port for reading, writing, and deleting Keychain secret payloads.
    var keychainAccess: any KeychainAccessPort {
        get { self[KeychainAccessPortKey.self] }
        set { self[KeychainAccessPortKey.self] = newValue }
    }
}

// MARK: - AuditChainPortKey

/// `DependencyKey` for `AuditChainPort`.
public enum AuditChainPortKey: DependencyKey {
    public static let liveValue: any AuditChainPort = UnimplementedAuditChainPort()
    public static let testValue: any AuditChainPort = UnimplementedAuditChainPort()
}

public extension DependencyValues {
    /// The port for appending and verifying the HMAC-gated mutation audit
    /// chain.
    var auditChain: any AuditChainPort {
        get { self[AuditChainPortKey.self] }
        set { self[AuditChainPortKey.self] = newValue }
    }
}
