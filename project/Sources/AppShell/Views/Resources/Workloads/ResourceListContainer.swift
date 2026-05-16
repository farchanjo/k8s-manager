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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Private views

    private var containerToolbar: some View {
        HStack(spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            countBadge
            Spacer()
            searchField
            // Fixed-frame trailing slot prevents the toolbar from shrinking
            // when `isLoading` toggles (otherwise the title + count + search
            // shift right/left on every load → "bar sumindo e aparecendo").
            ZStack {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    refreshButton
                }
            }
            .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 36)
    }

    @ViewBuilder
    private var countBadge: some View {
        if let count = itemCount {
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
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
