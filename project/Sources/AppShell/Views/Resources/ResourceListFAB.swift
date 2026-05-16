// Views/Resources/ResourceListFAB.swift — app_shell bounded context
// DDD role: View — floating action button for resource creation
// ADR ref: ADR-0066 (floating action button for resource creation)

import SwiftUI
import SharedKernel

// MARK: - FABCreatePath

/// The three creation paths exposed by the FAB popover per ADR-0066.
public enum FABCreatePath: Sendable, Hashable {
    /// Opens the YAML editor with a kind skeleton template pre-filled.
    case createFromScratch
    /// Reads the clipboard and pre-fills the editor if parseable as YAML or JSON.
    case pasteFromClipboard
    /// Forks the currently selected row (resets volatile metadata fields).
    case forkFromSelected
}

// MARK: - FABVisibilityPolicy

/// Determines whether the FAB should be visible for a given kind.
///
/// Per ADR-0066, the FAB is visible only when the kind's operation matrix
/// includes `create`. Kinds excluded: Node, Event, CSINode, CSIDriver.
public struct FABVisibilityPolicy: Sendable {

    /// Kinds that are explicitly excluded from FAB visibility.
    private static let excludedKinds: Set<String> = [
        "Node", "Event", "CSINode", "CSIDriver",
    ]

    /// Returns `true` when the FAB should be visible for the given kind.
    ///
    /// - Parameter kind: Kubernetes kind string (e.g. `"Deployment"`, `"Node"`).
    public static func isVisible(for kind: String) -> Bool {
        !excludedKinds.contains(kind)
    }
}

// MARK: - ResourceListFAB

/// Floating action button placed at the bottom-trailing corner of a resource list pane.
///
/// Displays a circular blue `+` button. Tapping it presents a three-path popover
/// (Create from scratch, Paste from clipboard, Fork from selected) per ADR-0066.
///
/// The button is hidden for kinds that do not support the `create` operation
/// (determined by `FABVisibilityPolicy`).
///
/// Usage:
/// ```swift
/// YourListView()
///     .overlay(alignment: .bottomTrailing) {
///         ResourceListFAB(
///             kind: "Deployment",
///             clusterId: clusterId,
///             hasSelection: viewModel.selectedId != nil
///         ) { path in
///             handleCreate(path)
///         }
///     }
/// ```
public struct ResourceListFAB: View {

    private let kind: String
    private let clusterId: ClusterId
    private let hasSelection: Bool
    private let onPath: (FABCreatePath) -> Void

    @State private var isPopoverPresented = false

    /// Creates a floating action button.
    ///
    /// - Parameters:
    ///   - kind: Kubernetes kind string — controls visibility and accessibility label.
    ///   - clusterId: Cluster the create action targets.
    ///   - hasSelection: `true` when exactly one row is selected (enables Fork path).
    ///   - onPath: Called with the chosen `FABCreatePath` when the operator selects one.
    public init(
        kind: String,
        clusterId: ClusterId,
        hasSelection: Bool = false,
        onPath: @escaping (FABCreatePath) -> Void
    ) {
        self.kind = kind
        self.clusterId = clusterId
        self.hasSelection = hasSelection
        self.onPath = onPath
    }

    public var body: some View {
        if FABVisibilityPolicy.isVisible(for: kind) {
            fabButton
                .padding(.bottom, 16)
                .padding(.trailing, 16)
        }
    }

    // MARK: Private views

    private var fabButton: some View {
        Button {
            isPopoverPresented = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityLabel("Create \(kind)")
        .accessibilityHint("Opens a menu with options to create a new resource from scratch, from clipboard, or by forking a selected row.")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            createPopover
        }
    }

    private var createPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Create \(kind)")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)

            Divider()

            createButton(
                label: "Create from scratch",
                systemImage: "doc.badge.plus",
                path: .createFromScratch
            )
            createButton(
                label: "Paste from clipboard",
                systemImage: "doc.on.clipboard",
                path: .pasteFromClipboard
            )
            createButton(
                label: hasSelection ? "Fork from selected" : "Fork from selected",
                systemImage: "doc.on.doc",
                path: .forkFromSelected,
                disabled: !hasSelection,
                disabledTooltip: "Select a row first"
            )
            .padding(.bottom, 8)
        }
        .frame(minWidth: 240)
    }

    private func createButton(
        label: String,
        systemImage: String,
        path: FABCreatePath,
        disabled: Bool = false,
        disabledTooltip: String? = nil
    ) -> some View {
        Button {
            isPopoverPresented = false
            onPath(path)
        } label: {
            Label(label, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(disabled ? (disabledTooltip ?? "") : "")
        .accessibilityLabel(label)
        .accessibilityHint(disabled ? (disabledTooltip ?? "") : "")
    }
}
