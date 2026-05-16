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

// MARK: - OperatorPreferencesPortKey

/// `DependencyKey` for `OperatorPreferencesPort`.
public enum OperatorPreferencesPortKey: DependencyKey {
    public static let liveValue: any OperatorPreferencesPort = UnimplementedOperatorPreferencesPort()
    public static let testValue: any OperatorPreferencesPort = UnimplementedOperatorPreferencesPort()
}

public extension DependencyValues {
    /// The port for loading and saving per-operator UX preferences.
    ///
    /// Consumed by `app_shell` on cold launch. Override `liveValue` in the
    /// composition root with the GRDB-backed adapter.
    var operatorPreferences: any OperatorPreferencesPort {
        get { self[OperatorPreferencesPortKey.self] }
        set { self[OperatorPreferencesPortKey.self] = newValue }
    }
}

// MARK: - PersistenceActorKey

/// `DependencyKey` for `PersistenceActor`.
///
/// The test value uses a `FakePersistenceWriter` that records calls without
/// touching any database file. Adapter targets override `liveValue` in the
/// composition root with a `GRDBWriterAdapter`-backed actor.
public enum PersistenceActorKey: DependencyKey {
    public static let liveValue: PersistenceActor = PersistenceActor(
        writer: UnimplementedPersistenceWriter()
    )
    public static let testValue: PersistenceActor = PersistenceActor(
        writer: FakePersistenceWriter()
    )
}

public extension DependencyValues {
    /// The single write gate for all SQLite traffic (ADR-0010).
    ///
    /// Adapters MUST route all mutations through this actor instead of
    /// calling GRDB directly. Reads may also be routed here for
    /// consistency, though WAL mode permits concurrent readers.
    var persistenceActor: PersistenceActor {
        get { self[PersistenceActorKey.self] }
        set { self[PersistenceActorKey.self] = newValue }
    }
}

// MARK: - UnimplementedPersistenceWriter

/// Crash-fast `PersistenceWriter` used as `liveValue` placeholder before
/// the adapter registers the real GRDB-backed writer.
public struct UnimplementedPersistenceWriter: PersistenceWriter {
    public init() {}

    public func read<T: Sendable>(
        _ work: @Sendable (any DatabaseHandle) throws -> T
    ) throws -> T {
        throw PersistenceActorError.operationFailed(
            underlying: "PersistenceWriter not configured — register GRDBWriterAdapter"
        )
    }

    public func write<T: Sendable>(
        _ work: @Sendable (any DatabaseHandle) throws -> T
    ) throws -> T {
        throw PersistenceActorError.operationFailed(
            underlying: "PersistenceWriter not configured — register GRDBWriterAdapter"
        )
    }

    public func barrier() async {}
}

// MARK: - FakePersistenceWriter

/// In-memory `PersistenceWriter` used as `testValue`. Immediately executes
/// closures with a `NullDatabaseHandle`; no file I/O occurs.
public struct FakePersistenceWriter: PersistenceWriter {
    public init() {}

    public func read<T: Sendable>(
        _ work: @Sendable (any DatabaseHandle) throws -> T
    ) throws -> T {
        try work(NullDatabaseHandle())
    }

    public func write<T: Sendable>(
        _ work: @Sendable (any DatabaseHandle) throws -> T
    ) throws -> T {
        try work(NullDatabaseHandle())
    }

    public func barrier() async {}
}

// MARK: - NullDatabaseHandle

/// No-op `DatabaseHandle` used by `FakePersistenceWriter` in tests.
public struct NullDatabaseHandle: DatabaseHandle {
    public init() {}
}
