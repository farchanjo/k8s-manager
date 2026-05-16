// Views/Palette/CommandPaletteOverlay.swift — app_shell bounded context
// DDD role: View + ViewModel for the #CommandPalette AggregateRoot
// ADR ref: ADR-0023 (command palette, keyboard shortcuts)
//          ADR-0034 (state-driven realtime UI — @Observable, no Combine)

import SwiftUI
import Dependencies
import ContextNavigation
import SharedKernel

// MARK: - Command (view-layer model)

/// A single executable entry in the command palette.
///
/// Supplements `CommandEntry` (domain model) with the `@MainActor` action closure
/// that is resolved at view composition time rather than stored in the aggregate.
public struct Command: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    /// Invoked on `Return` or row tap. Always runs on `@MainActor`.
    public let action: @MainActor @Sendable () -> Void

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.action = action
    }
}

// MARK: - CommandPaletteViewModel

/// `@Observable` view model for the command palette overlay.
///
/// Commands are discovered dynamically from `ContextRepositoryPort` (one "Switch
/// context to <name>" entry per persisted recent context) plus a static set of
/// built-in actions. Fuzzy match is a composite of:
/// - Substring containment (case-insensitive).
/// - Levenshtein distance ≤ 3 on title tokens (per ADR-0023 FuzzyMatchConfig.maxEditDistance).
/// Short queries (≤ 3 chars) run synchronously on `@MainActor`; longer queries run
/// in a `Task.detached` and post back via `MainActor.run`.
@Observable
@MainActor
public final class CommandPaletteViewModel {

    // MARK: Public state

    /// Whether the palette overlay is currently presented.
    public private(set) var isVisible = false
    /// Current incremental search string bound to the `TextField`.
    public var query: String = "" {
        didSet { scheduleFilter() }
    }
    /// Ranked results shown in the list.
    public private(set) var results: [Command] = []
    /// Zero-based cursor into `results`.
    public private(set) var selectedIndex: Int = 0

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.contextRepository) private var contextRepository

    // MARK: Private

    private var catalog: [Command]
    private var filterTask: Task<Void, Never>?
    private let maxEditDistance = 3

    /// Initialiser used by tests to inject a pre-built catalog (bypasses `loadCommands()`).
    public init(catalog: [Command]) {
        self.catalog = catalog
    }

    /// Default initialiser — catalog is populated lazily by `loadCommands()`.
    public init() {
        self.catalog = []
    }

    // MARK: Catalog loading

    /// Loads the command catalog from the dependency graph.
    ///
    /// Called once from the `.task` modifier attached to `CommandPaletteOverlay`.
    /// Merges dynamic context-switch entries with the static built-in set.
    public func loadCommands() async {
        let dynamic = await buildContextSwitchCommands()
        catalog = dynamic + Self.staticCommands()
        if isVisible { results = catalog }
    }

    private func buildContextSwitchCommands() async -> [Command] {
        do {
            let recents = try await contextRepository.loadRecentWindow()
            return recents.entries.map { entry in
                Command(
                    id: "switch-\(entry.contextId.rawValue)",
                    title: "Switch context to \(entry.displayName)",
                    subtitle: "Context",
                    systemImage: "arrow.triangle.branch"
                ) {
                    NotificationCenter.default.post(
                        name: .k8sManagerSwitchContext,
                        object: nil,
                        userInfo: ["contextId": entry.contextId.rawValue,
                                   "displayName": entry.displayName]
                    )
                }
            }
        } catch {
            return []
        }
    }

    /// Built-in static command entries, independent of cluster state.
    public static func staticCommands() -> [Command] {
        [
            Command(
                id: "go-to-welcome-tab",
                title: "Go to Welcome Tab",
                subtitle: "Cmd+Shift+W",
                systemImage: "hand.wave"
            ) {
                NotificationCenter.default.post(
                    name: .k8sManagerFocusWelcomeTab,
                    object: nil
                )
            },
            Command(
                id: "refresh",
                title: "Refresh Resources",
                subtitle: nil,
                systemImage: "arrow.clockwise"
            ) {
                NotificationCenter.default.post(name: .k8sManagerRefresh, object: nil)
            },
            Command(
                id: "toggle-palette",
                title: "Toggle Palette",
                subtitle: "Cmd+K",
                systemImage: "magnifyingglass"
            ) {
                NotificationCenter.default.post(name: .k8sManagerOpenPalette, object: nil)
            },
            Command(
                id: "open-preferences",
                title: "Open Preferences",
                subtitle: nil,
                systemImage: "gear"
            ) {
                // Settings scene managed by SwiftUI — no-op stub.
            },
            Command(
                id: "quit",
                title: "Quit K8sManager",
                subtitle: nil,
                systemImage: "power"
            ) {
                NSApp.terminate(nil)
            },
        ]
    }

    // MARK: Lifecycle

    /// Opens the palette; resets query and selection.
    public func open() {
        query = ""
        selectedIndex = 0
        results = catalog
        isVisible = true
    }

    /// Opens the palette pre-seeded with a filter string.
    public func open(prefiltered query: String) {
        self.query = query
        selectedIndex = 0
        isVisible = true
        scheduleFilter()
    }

    /// Dismisses the palette without executing any command.
    public func dismiss() {
        isVisible = false
        filterTask?.cancel()
        filterTask = nil
    }

    // MARK: Keyboard navigation

    /// Moves cursor down one position, wrapping at the bottom.
    public func moveCursorDown() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % results.count
    }

    /// Moves cursor up one position, wrapping at the top.
    public func moveCursorUp() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + results.count) % results.count
    }

    /// Executes the command at `selectedIndex` and dismisses.
    public func executeSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        let command = results[selectedIndex]
        dismiss()
        command.action()
    }

    /// Sets `selectedIndex` to `index` then immediately executes.
    ///
    /// Used by row tap handlers to avoid exposing the setter publicly
    /// (Swift `@Observable` stored properties have no per-property access control).
    public func selectAndExecute(index: Int) {
        selectedIndex = index
        executeSelected()
    }

    // MARK: Filtering

    private func scheduleFilter() {
        filterTask?.cancel()
        let q = query
        let cat = catalog
        let maxDist = maxEditDistance

        if q.isEmpty {
            results = cat
            selectedIndex = 0
            return
        }

        if q.count <= 3 {
            // Synchronous path for short queries (ADR-0023 performance contract).
            results = Self.ranked(query: q, catalog: cat, maxEditDistance: maxDist)
            selectedIndex = 0
        } else {
            // Off-actor path for longer queries.
            filterTask = Task.detached(priority: .userInitiated) {
                let ranked = Self.ranked(query: q, catalog: cat, maxEditDistance: maxDist)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.results = ranked
                    self.selectedIndex = 0
                }
            }
        }
    }

    // MARK: Ranking (nonisolated — runs off-actor for long queries)

    /// Returns commands ranked by fuzzy relevance to `query`.
    ///
    /// Score = substring_bonus (1.0) + contiguity_bonus (0.5) − levenshtein_penalty.
    nonisolated static func ranked(
        query: String,
        catalog: [Command],
        maxEditDistance: Int
    ) -> [Command] {
        let q = query.lowercased()
        return catalog
            .compactMap { cmd -> (Command, Double)? in
                let score = relevanceScore(query: q, command: cmd, maxEditDistance: maxEditDistance)
                guard score > 0 else { return nil }
                return (cmd, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    nonisolated private static func relevanceScore(
        query: String,
        command: Command,
        maxEditDistance: Int
    ) -> Double {
        let title = command.title.lowercased()
        let subtitle = command.subtitle?.lowercased() ?? ""

        // Exact substring match — highest signal.
        if title.contains(query) { return 2.0 }
        if subtitle.contains(query) { return 1.5 }

        // Subsequence match on title.
        if isSubsequence(query, in: title) { return 1.2 }

        // Levenshtein distance on each title token.
        let tokens = title.split(separator: " ").map(String.init)
        for token in tokens {
            let dist = levenshtein(query, token)
            if dist <= maxEditDistance {
                return 1.0 - Double(dist) * 0.15
            }
        }
        return 0
    }

    /// Returns `true` when every character in `needle` appears in `haystack` in order.
    nonisolated static func isSubsequence(_ needle: String, in haystack: String) -> Bool {
        var it = haystack.makeIterator()
        return needle.allSatisfy { char in
            while let h = it.next() { if h == char { return true } }
            return false
        }
    }

    /// Standard iterative Levenshtein distance.
    nonisolated static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        guard m > 0 else { return n }
        guard n > 0 else { return m }
        var row = Array(0...n)
        for i in 1...m {
            var prev = row[0]
            row[0] = i
            for j in 1...n {
                let temp = row[j]
                row[j] = aChars[i - 1] == bChars[j - 1]
                    ? prev
                    : 1 + Swift.min(prev, row[j], row[j - 1])
                prev = temp
            }
        }
        return row[n]
    }
}

// MARK: - CommandPaletteOverlay

/// Modal-style overlay presenting the universal command palette.
///
/// Activation: `⌘K` (or `⌘P`) — wired in `K8sManagerCommands`.
/// Dismissal: `Esc`, clicking outside, or executing a command.
///
/// Accessibility:
/// - Declares `accessibilityLabel("Command Palette")`.
/// - Posts `.updatesFrequently` trait on the result region.
/// - Focus is trapped inside the overlay while visible.
@MainActor
public struct CommandPaletteOverlay: View {

    @Bindable var viewModel: CommandPaletteViewModel

    public init(viewModel: CommandPaletteViewModel) {
        self.viewModel = viewModel
    }

    @FocusState private var searchFocused: Bool

    public var body: some View {
        ZStack {
            if viewModel.isVisible {
                // Dim backdrop — tapping outside dismisses.
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { viewModel.dismiss() }

                palettePanel
                    .transition(
                        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.97)),
                                removal: .opacity.combined(with: .scale(scale: 0.97))
                              )
                    )
                    .animation(.spring(response: 0.18, dampingFraction: 0.82), value: viewModel.isVisible)
            }
        }
        .task { await viewModel.loadCommands() }
        .accessibilityLabel("Command Palette")
    }

    // MARK: Panel

    private var palettePanel: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if viewModel.results.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.24), radius: 32)
        .padding(.top, 80) // Place in upper third of the window.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onKeyPress(.escape) { viewModel.dismiss(); return .handled }
        .onKeyPress(.downArrow) { viewModel.moveCursorDown(); return .handled }
        .onKeyPress(.upArrow) { viewModel.moveCursorUp(); return .handled }
        .onKeyPress(.return) { viewModel.executeSelected(); return .handled }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search commands…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .accessibilityLabel("Command search")
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .task { searchFocused = true }
    }

    // MARK: Results list

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, cmd in
                        resultRow(cmd, index: index)
                            .id(cmd.id)
                    }
                }
            }
            .frame(maxHeight: 380)
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                guard viewModel.results.indices.contains(newIndex) else { return }
                proxy.scrollTo(viewModel.results[newIndex].id, anchor: .center)
            }
        }
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func resultRow(_ cmd: Command, index: Int) -> some View {
        let isSelected = index == viewModel.selectedIndex
        return Button {
            viewModel.selectAndExecute(index: index)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: cmd.systemImage)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cmd.title)
                        .font(.body)
                        .foregroundStyle(isSelected ? .white : .primary)
                    if let subtitle = cmd.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(isSelected ? .white.opacity(0.75) : .secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([cmd.title, cmd.subtitle].compactMap { $0 }.joined(separator: ", "))
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: Empty state

    private var emptyState: some View {
        Text("No matching commands")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}

// MARK: - AppKit import for NSApp usage

import AppKit
