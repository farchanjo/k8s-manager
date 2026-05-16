// Views/Inspector/ResourceInspectorPanel.swift — app_shell bounded context
// DDD role: View — Inspector trailing column content area
// ADR ref: ADR-0073 (inspector trailing column substitutes resource detail tabs)

import SwiftUI

// MARK: - ResourceInspectorPanel

/// Content view rendered inside the `.inspector(isPresented:)` column.
///
/// Dispatches on `viewModel.selectedKey`:
/// - `nil` → `InspectorEmptyStateView` (no row selected).
/// - non-nil → first non-nil view from `ResourceInspectorContent.resolve(for:)`.
///
/// The provider chain in `ResourceInspectorContent.allProviders` currently
/// contains only `GenericResourceInspectorProvider` (Wave 3 stub). Per-kind
/// providers are prepended in subsequent waves without touching this view.
@MainActor
public struct ResourceInspectorPanel: View {

    // MARK: Input

    /// View model from the environment — drives `selectedKey` and visibility.
    private let viewModel: ResourceInspectorViewModel?

    // MARK: Init

    public init(viewModel: ResourceInspectorViewModel?) {
        self.viewModel = viewModel
    }

    // MARK: Body

    public var body: some View {
        Group {
            if let vm = viewModel {
                if let key = vm.selectedKey,
                   let resolved = ResourceInspectorContent.resolve(for: key) {
                    resolved
                } else if vm.selectedKey != nil {
                    // Provider returned nil — kind has no registered inspector yet.
                    // Fall through to empty state with a hint.
                    InspectorNoContentView()
                } else {
                    // No row selected.
                    InspectorEmptyStateView()
                }
            } else {
                // Inspector not wired (preview / menu bar scene).
                InspectorEmptyStateView()
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
        .background(.background)
    }
}

// MARK: - InspectorEmptyStateView

/// Shown when no row is selected and the Inspector column is open.
private struct InspectorEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No Selection")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Select a resource row to see its details here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - InspectorNoContentView

/// Shown when a row is selected but no provider covers its kind yet.
private struct InspectorNoContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Inspector Coming Soon")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("A detailed inspector for this resource kind will be available in a future release. Use \"Open in Tab\" from the context menu for now.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
