// Views/Resources/Workloads/ResourceListContainer.swift — app_shell bounded context
// DDD role: View — shared container for all workload list views
// ADR ref: ADR-0050 (Onda 2 resource list views)

import SwiftUI

// MARK: - ResourceListContainer

/// Shared scaffold wrapping any kind-specific resource table.
///
/// Provides a consistent chrome: title bar, namespace picker, search field,
/// refresh button, and a count badge. The table itself is slotted via
/// `@ViewBuilder content`.
public struct ResourceListContainer<Content: View>: View {

    private let title: String
    private let itemCount: Int?
    private let isLoading: Bool
    private let namespace: Binding<String?>
    private let searchText: Binding<String>
    private let onRefresh: () async -> Void
    private let content: Content

    public init(
        title: String = "",
        itemCount: Int? = nil,
        isLoading: Bool = false,
        namespace: Binding<String?> = .constant(nil),
        searchText: Binding<String> = .constant(""),
        onRefresh: @escaping () async -> Void = {},
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.itemCount = itemCount
        self.isLoading = isLoading
        self.namespace = namespace
        self.searchText = searchText
        self.onRefresh = onRefresh
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            containerToolbar
            Divider()
            contentArea
        }
        // Explicit maxHeight anchor guarantees the overlay placed by each
        // *ListView caller always binds to the full panel frame, not to the
        // Table's variable intrinsic height during the skeleton→data transition.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Private views

    private var containerToolbar: some View {
        HStack(spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            // Reserve a fixed leading slot for the count badge so the
            // surrounding HStack geometry stays stable when itemCount toggles
            // between nil (skeleton phase) and N (loaded). Without this slot,
            // the Spacer expands/collapses and the search field slides
            // horizontally — the artifact users perceive as "search appears
            // from nowhere" during loading. ADR-0021 §toolbar stability.
            countBadge
                .frame(minWidth: 32, alignment: .leading)
            Spacer()
            searchField
            // Fixed-frame trailing slot keeps toolbar geometry stable while
            // the loading indicator and refresh button swap. Both views stay
            // in the tree and are toggled via opacity so SwiftUI never
            // cross-fades them — eliminates the "subtitle fade" artifact.
            ZStack {
                ProgressView()
                    .controlSize(.small)
                    .opacity(isLoading ? 1 : 0)
                refreshButton
                    .opacity(isLoading ? 0 : 1)
            }
            .frame(width: 20, height: 20)
            .animation(.none, value: isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 36)
    }

    /// Always-present count badge whose visibility is toggled via opacity.
    ///
    /// An `if let` would flip the badge's structural identity between nil
    /// (skeleton phase) and `Some(n)` (loaded). SwiftUI's default transition
    /// for that flip is a fade, producing the 1–2 frame blink users observed.
    /// Keeping the Text node permanently in the tree (with a placeholder
    /// string when nil) eliminates the flip entirely. ADR-0021 / ADR-0071.
    private var countBadge: some View {
        Text(itemCount.map { "\($0)" } ?? "0")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .opacity(itemCount != nil ? 1 : 0)
            .animation(.none, value: itemCount)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .imageScale(.small)
            TextField("Search", text: searchText)
                .textFieldStyle(.plain)
                .font(.callout)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
        .frame(minWidth: 160, maxWidth: 240)
    }

    private var refreshButton: some View {
        Button {
            Task { await onRefresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .imageScale(.small)
        }
        .buttonStyle(.borderless)
        .help("Refresh")
    }

    private var contentArea: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
