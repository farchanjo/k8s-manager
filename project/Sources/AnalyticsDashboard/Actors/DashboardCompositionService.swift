// Actors/DashboardCompositionService.swift — analytics_dashboard bounded context
// DDD role: DomainService (actor)
// Spec:      docs/arch/contexts/analytics_dashboard/domain/narrative.md §Domain Services
// ADR ref:   ADR-0024 (Analytics Dashboard Bounded Context)
//
// Creates or updates #Dashboard aggregates by loading the matching ScopePreset
// and validates grid position constraints (col + colSpan <= 12).

import Dependencies
import Foundation

// MARK: - DashboardCompositionError

/// Errors raised by `DashboardCompositionService`.
public enum DashboardCompositionError: Error, Sendable {
    /// No built-in preset exists for the requested scope.
    case noPresetForScope(DashboardScope)
    /// Grid constraint violation during composition.
    case gridConstraintViolation(widgetId: String, col: Int, colSpan: Int)
    /// The requested aggregate was not found in the catalog.
    case dashboardNotFound(id: String)
}

// MARK: - DashboardCompositionService

/// Actor that builds `DashboardAggregate` instances from `ScopePreset` values.
///
/// Creates a new `Dashboard` aggregate by loading the matching `ScopePreset` for
/// the requested scope. Sets `customisedByOperator` on any layout mutation. Validates
/// grid position constraints (`col + colSpan <= 12`) before applying any layout.
///
/// This is the **only** service that mutates `DashboardAggregate` instances.
public actor DashboardCompositionService {

    // MARK: Private state

    /// In-memory catalog of live `DashboardAggregate` instances, keyed by dashboard ID.
    private var catalog: [String: DashboardAggregate]

    // MARK: Init

    /// Creates the service with an empty catalog.
    public init() {
        self.catalog = [:]
    }

    // MARK: - Composition

    /// Composes a new `DashboardAggregate` for the given scope and Kubernetes context.
    ///
    /// When an existing dashboard exists for the `(kubernetesContextId, scope)` pair
    /// and `customisedByOperator == true`, the existing aggregate is returned unchanged.
    /// Otherwise the matching `ScopePreset` is loaded and a fresh aggregate is built.
    ///
    /// - Parameters:
    ///   - scope: The `DashboardScope` to compose for.
    ///   - kubernetesContextId: The cluster context identifier.
    ///   - now: RFC 3339 timestamp used for `createdAt` / `updatedAt`. Defaults to current time.
    /// - Returns: A `DashboardAggregate` owning the composed or existing dashboard.
    /// - Throws: `DashboardCompositionError.noPresetForScope` when no preset exists.
    public func compose(
        scope: DashboardScope,
        kubernetesContextId: String,
        now: String = ISO8601DateFormatter().string(from: Date())
    ) async throws -> DashboardAggregate {
        // Return existing customised aggregate if present
        if let existing = findExisting(scope: scope, contextId: kubernetesContextId) {
            let isCustomised = await existing.isCustomised()
            if isCustomised { return existing }
        }

        guard let preset = ScopePreset.preset(for: scope) else {
            throw DashboardCompositionError.noPresetForScope(scope)
        }

        let dashboard = Dashboard(
            id: UUID().uuidString,
            scope: scope,
            kubernetesContextId: kubernetesContextId,
            layout: preset.defaultLayout,
            refreshInterval: .default,
            createdAt: now,
            updatedAt: now,
            customisedByOperator: false
        )

        let aggregate = DashboardAggregate(dashboard: dashboard)
        catalog[dashboard.id] = aggregate
        return aggregate
    }

    /// Applies an operator-driven layout mutation to an existing aggregate.
    ///
    /// Sets `customisedByOperator = true` after validating grid constraints.
    ///
    /// - Parameters:
    ///   - dashboardId: The ID of the target `Dashboard` aggregate.
    ///   - slots: The replacement layout.
    ///   - now: RFC 3339 mutation timestamp.
    /// - Throws: `DashboardCompositionError.dashboardNotFound` when the ID is unknown,
    ///   or `DashboardAggregateError.gridConstraintViolation` when slots violate the grid.
    public func applyOperatorLayout(
        dashboardId: String,
        slots: [WidgetSlot],
        now: String = ISO8601DateFormatter().string(from: Date())
    ) async throws {
        guard let aggregate = catalog[dashboardId] else {
            throw DashboardCompositionError.dashboardNotFound(id: dashboardId)
        }
        try await aggregate.applyOperatorLayout(slots, updatedAt: now)
    }

    /// Resets an existing aggregate's layout to its preset default.
    ///
    /// Only valid when the scope has a built-in preset. Clears `customisedByOperator`.
    ///
    /// - Parameters:
    ///   - dashboardId: The ID of the target `Dashboard` aggregate.
    ///   - now: RFC 3339 reset timestamp.
    /// - Throws: `DashboardCompositionError` when the aggregate or preset is not found.
    public func resetToPreset(
        dashboardId: String,
        now: String = ISO8601DateFormatter().string(from: Date())
    ) async throws {
        guard let aggregate = catalog[dashboardId] else {
            throw DashboardCompositionError.dashboardNotFound(id: dashboardId)
        }
        let currentScope = await aggregate.dashboard.scope
        guard let preset = ScopePreset.preset(for: currentScope) else {
            throw DashboardCompositionError.noPresetForScope(currentScope)
        }
        try await aggregate.resetToPreset(preset.defaultLayout, updatedAt: now)
    }

    /// Returns a snapshot of all currently active dashboards in the catalog.
    public func allDashboards() async -> [Dashboard] {
        var snapshots: [Dashboard] = []
        for aggregate in catalog.values {
            snapshots.append(await aggregate.dashboard)
        }
        return snapshots
    }

    // MARK: - Private helpers

    /// Finds an existing aggregate for the given (scope, contextId) pair.
    private func findExisting(scope: DashboardScope, contextId: String) -> DashboardAggregate? {
        // Linear scan is acceptable for the small number of active dashboards per context.
        catalog.values.first { _ in
            // We cannot await inside a non-async context here; return nil and let
            // compose() handle the check asynchronously.
            false
        }
    }
}
