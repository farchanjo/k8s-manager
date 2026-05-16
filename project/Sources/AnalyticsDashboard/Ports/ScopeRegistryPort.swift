// Ports/ScopeRegistryPort.swift — analytics_dashboard bounded context
// DDD role: Port (primary — outbound to scope registry)
// Spec:      docs/arch/contexts/analytics_dashboard/domain/narrative.md §Ports
// ADR ref:   ADR-0024 (Analytics Dashboard Bounded Context)
//
// Consumed by `app_shell` sidebar via `DashboardCatalogReadModel`.

import Foundation

// MARK: - ScopeRegistryPort

/// Provides the list of available scopes for the currently selected Kubernetes context.
///
/// Consumed by `app_shell` sidebar via `DashboardCatalogReadModel`. Drives the sidebar
/// scope picker UI and the list of dashboards available to the operator.
public protocol ScopeRegistryPort: Sendable {
    /// Returns all `DashboardScope` variants available for the given Kubernetes context.
    ///
    /// - Parameter kubernetesContextId: The cluster context identifier from
    ///   `cluster_connectivity`.
    /// - Returns: Ordered list of available scopes. Never empty for a valid context.
    /// - Throws: `ScopeRegistryError` on connectivity or decode failure.
    func availableScopes(
        forContext kubernetesContextId: String
    ) async throws -> [DashboardScope]

    /// Returns `true` when the given scope has an operator-customised layout in the catalog.
    ///
    /// - Parameters:
    ///   - scope: The scope to check.
    ///   - kubernetesContextId: The cluster context identifier.
    func hasCustomLayout(
        for scope: DashboardScope,
        inContext kubernetesContextId: String
    ) async throws -> Bool
}

// MARK: - ScopeRegistryError

/// Errors raised by `ScopeRegistryPort` implementations.
public enum ScopeRegistryError: Error, Sendable {
    /// Port has not been registered in this process.
    case unimplemented
    /// The context identifier is not known to the registry.
    case unknownContext(String)
    /// Connectivity failure while listing scopes.
    case transportError(detail: String)
}

// MARK: - UnimplementedScopeRegistryPort

/// Crash-fast sentinel used as `liveValue` / `testValue` until an adapter registers.
public struct UnimplementedScopeRegistryPort: ScopeRegistryPort {
    public init() {}

    public func availableScopes(forContext _: String) async throws -> [DashboardScope] {
        throw ScopeRegistryError.unimplemented
    }

    public func hasCustomLayout(for _: DashboardScope, inContext _: String) async throws -> Bool {
        throw ScopeRegistryError.unimplemented
    }
}
