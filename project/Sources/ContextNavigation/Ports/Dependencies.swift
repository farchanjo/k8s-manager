// Ports/Dependencies.swift — context_navigation bounded context
// DI registry via pointfreeco/swift-dependencies
// ADR ref: ADR-0020 (dependency injection strategy)

import Dependencies
import SharedKernel

// MARK: - ContextRepositoryPortKey

/// `DependencyKey` for `ContextRepositoryPort`.
///
/// `liveValue` and `testValue` are both the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. Adapter targets override `liveValue`
/// at composition root.
public enum ContextRepositoryPortKey: DependencyKey {
    public static let liveValue: any ContextRepositoryPort = UnimplementedContextRepositoryPort()
    public static let testValue: any ContextRepositoryPort = UnimplementedContextRepositoryPort()
}

public extension DependencyValues {
    /// The port responsible for persisting pins, recents, and the last active
    /// context across launches.
    var contextRepository: any ContextRepositoryPort {
        get { self[ContextRepositoryPortKey.self] }
        set { self[ContextRepositoryPortKey.self] = newValue }
    }
}

// MARK: - ActiveContextWatchPortKey

/// `DependencyKey` for `ActiveContextWatchPort`.
public enum ActiveContextWatchPortKey: DependencyKey {
    public static let liveValue: any ActiveContextWatchPort = UnimplementedActiveContextWatchPort()
    public static let testValue: any ActiveContextWatchPort = UnimplementedActiveContextWatchPort()
}

public extension DependencyValues {
    /// The port that streams `ActiveContextChanged` domain events to consumers.
    var activeContextWatch: any ActiveContextWatchPort {
        get { self[ActiveContextWatchPortKey.self] }
        set { self[ActiveContextWatchPortKey.self] = newValue }
    }
}

// MARK: - SidebarReadModelPortKey

/// `DependencyKey` for `SidebarReadModelPort`.
public enum SidebarReadModelPortKey: DependencyKey {
    public static let liveValue: any SidebarReadModelPort = UnimplementedSidebarReadModelPort()
    public static let testValue: any SidebarReadModelPort = UnimplementedSidebarReadModelPort()
}

public extension DependencyValues {
    /// The port that provides the combined sidebar read model to `app_shell`.
    var sidebarReadModel: any SidebarReadModelPort {
        get { self[SidebarReadModelPortKey.self] }
        set { self[SidebarReadModelPortKey.self] = newValue }
    }
}
