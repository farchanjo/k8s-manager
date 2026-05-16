// Actors/DashboardAggregate.swift — analytics_dashboard bounded context
// DDD role: AggregateRoot (actor wrapper)
// Spec:      docs/arch/contexts/analytics_dashboard/domain/narrative.md §Aggregate Roots
// ADR ref:   ADR-0024 (Analytics Dashboard Bounded Context)
// ADR ref:   ADR-0011 (Swift actor isolation)
//
// `DashboardAggregate` is the actor that owns the mutable `Dashboard` state
// for one (kubernetesContextId, scope) pair. All mutations go through this actor.

import Foundation

// MARK: - DashboardAggregateError

/// Errors raised by `DashboardAggregate` state-mutation operations.
public enum DashboardAggregateError: Error, Sendable {
    /// The proposed layout contains a `WidgetSlot` whose `col + colSpan > 12`
    /// violating the grid invariant (spec §7).
    case gridConstraintViolation(widgetId: String, col: Int, colSpan: Int)
    /// The proposed `WidgetSlot` references a `widgetId` that does not exist
    /// in the active widget catalog.
    case unknownWidgetId(String)
    /// An attempt was made to reset a customised layout without explicitly
    /// providing a new preset (guard against accidental data loss).
    case customisedLayoutProtected
}

// MARK: - DashboardAggregate

/// Actor that owns the mutable `Dashboard` state for one `(kubernetesContextId, scope)` pair.
///
/// All mutations — layout replacement, refresh interval change, and preset reset —
/// go through this actor. `DashboardCompositionService` is the only service that
/// creates or directly mutates `DashboardAggregate` instances.
///
/// Invariants enforced on every mutation:
/// - `col + colSpan <= 12` for every `WidgetSlot` (spec §7).
/// - `customisedByOperator` is set to `true` on any operator-driven layout mutation.
public actor DashboardAggregate {

    // MARK: Public state

    /// The current immutable `Dashboard` value snapshot.
    public private(set) var dashboard: Dashboard

    // MARK: Init

    /// Initialises the aggregate with an existing `Dashboard` value.
    ///
    /// - Parameter dashboard: The initial dashboard state (from storage or preset).
    public init(dashboard: Dashboard) {
        self.dashboard = dashboard
    }

    // MARK: - Queries

    /// Returns the current layout as a snapshot.
    public func currentLayout() -> [WidgetSlot] {
        dashboard.layout
    }

    /// Returns `true` when the operator has customised this dashboard's layout.
    public func isCustomised() -> Bool {
        dashboard.customisedByOperator
    }

    // MARK: - Mutations

    /// Replaces the layout with the operator-provided slots.
    ///
    /// Sets `customisedByOperator = true`. Validates every slot's grid constraint.
    ///
    /// - Parameters:
    ///   - slots: The new layout. Must satisfy `col + colSpan <= 12` for every slot.
    ///   - updatedAt: RFC 3339 timestamp for the mutation; typically from the system clock.
    /// - Throws: `DashboardAggregateError.gridConstraintViolation` when any slot exceeds
    ///   the 12-column boundary.
    public func applyOperatorLayout(_ slots: [WidgetSlot], updatedAt: String) throws {
        try validateGridConstraints(slots)
        dashboard = dashboard.withCustomLayout(slots, updatedAt: updatedAt)
    }

    /// Resets the layout to the given preset slots.
    ///
    /// Clears `customisedByOperator`. Only `DashboardCompositionService` should call this;
    /// direct operator reset is blocked (guard against accidental data loss).
    ///
    /// - Parameters:
    ///   - presetSlots: The preset's `defaultLayout`.
    ///   - updatedAt: RFC 3339 timestamp for the reset.
    /// - Throws: `DashboardAggregateError.gridConstraintViolation` when any preset slot
    ///   exceeds the grid boundary.
    public func resetToPreset(_ presetSlots: [WidgetSlot], updatedAt: String) throws {
        try validateGridConstraints(presetSlots)
        let reset = Dashboard(
            id: dashboard.id,
            scope: dashboard.scope,
            kubernetesContextId: dashboard.kubernetesContextId,
            layout: presetSlots,
            refreshInterval: dashboard.refreshInterval,
            createdAt: dashboard.createdAt,
            updatedAt: updatedAt,
            customisedByOperator: false
        )
        dashboard = reset
    }

    /// Updates the auto-refresh cadence.
    ///
    /// - Parameters:
    ///   - interval: The new refresh cadence.
    ///   - updatedAt: RFC 3339 timestamp.
    public func applyRefreshInterval(_ interval: RefreshInterval, updatedAt: String) {
        dashboard = dashboard.withRefreshInterval(interval, updatedAt: updatedAt)
    }

    // MARK: - Private helpers

    /// Validates that every slot satisfies `position.col + position.colSpan <= 12`.
    private func validateGridConstraints(_ slots: [WidgetSlot]) throws {
        for slot in slots {
            guard slot.position.isWithinGridBounds else {
                throw DashboardAggregateError.gridConstraintViolation(
                    widgetId: slot.widgetId,
                    col: slot.position.col,
                    colSpan: slot.position.colSpan
                )
            }
        }
    }
}
