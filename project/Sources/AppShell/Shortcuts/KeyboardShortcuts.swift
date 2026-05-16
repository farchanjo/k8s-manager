// Shortcuts/KeyboardShortcuts.swift — app_shell bounded context
// DDD role: ViewModifier + Commands (ShortcutDispatchService adapter)
// ADR ref: ADR-0023 (keyboard shortcut vocabulary, hybrid Cmd + k9s bindings)
//          ADR-0034 (state-driven realtime UI)

import SwiftUI

// MARK: - K8sManagerCommands

/// Declares all global `⌘`-prefixed bindings in the macOS menu bar / SwiftUI commands graph.
///
/// Applied via `.commands { K8sManagerCommands() }` on `K8sManagerRootScene`.
/// Per ADR-0023 § Global Cmd bindings:
/// - ⌘K / ⌘P → toggle command palette
/// - ⌘, → preferences (stub)
/// - ⌘L → focus search
/// - ⌘R → refresh current view
/// - ⌘⇧C → switch context (palette pre-filtered)
/// - ⌘1–⌘9 → jump to sidebar feature by index
public struct K8sManagerCommands: Commands {

    /// Injected from the root scene so commands can mutate shared state.
    @Binding var isPaletteVisible: Bool
    @Binding var selectedFeature: Feature?

    public init(
        isPaletteVisible: Binding<Bool>,
        selectedFeature: Binding<Feature?>
    ) {
        self._isPaletteVisible = isPaletteVisible
        self._selectedFeature = selectedFeature
    }

    public var body: some Commands {
        CommandMenu("Navigate") {
            // ⌘K — toggle palette (primary activation per ADR-0023)
            Button("Command Palette") {
                isPaletteVisible.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)
            .accessibilityLabel("Toggle command palette")

            // ⌘P — palette alternate activation
            Button("Search Commands") {
                isPaletteVisible.toggle()
            }
            .keyboardShortcut("p", modifiers: .command)
            .accessibilityLabel("Open command palette")

            Divider()

            // ⌘⇧C — switch context via palette pre-filtered
            Button("Switch Context…") {
                isPaletteVisible = true
                // Pre-filter token set via notification so palette receives "switch context".
                NotificationCenter.default.post(
                    name: .palettePrefilter,
                    object: nil,
                    userInfo: ["query": "switch context"]
                )
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .accessibilityLabel("Switch Kubernetes context")

            // ⌘1–⌘9 — jump to sidebar feature by index (0-based Feature.allCases)
            ForEach(Feature.allCases.prefix(9).indices, id: \.self) { index in
                let feature = Feature.allCases[index]
                Button("Jump to \(feature.title)") {
                    selectedFeature = feature
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .accessibilityLabel("Navigate to \(feature.title)")
            }
        }

        CommandGroup(after: .sidebar) {
            // ⌘L — focus search (resource browser filter field)
            Button("Focus Search") {
                NotificationCenter.default.post(name: .focusSearch, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)
            .accessibilityLabel("Focus resource search field")

            // ⌘R — refresh current view
            Button("Refresh") {
                NotificationCenter.default.post(name: .refreshCurrentView, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel("Refresh current view")
        }

        CommandGroup(replacing: .appSettings) {
            // ⌘, — preferences (stub; Settings window opened by SwiftUI automatically on macOS 13+)
            Button("Settings…") {
                // SwiftUI's Settings scene handles this; this entry surfaces in the menu.
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Open Settings")
        }
    }
}

// MARK: - Notification names (internal broadcast bus for command dispatch)

public extension Notification.Name {
    /// Posted when Cmd+L is pressed — resource browser subscribes via `.onReceive`.
    static let focusSearch = Notification.Name("appShell.focusSearch")
    /// Posted when Cmd+R is pressed — active view subscribes to trigger its reload.
    static let refreshCurrentView = Notification.Name("appShell.refreshCurrentView")
    /// Posted when Cmd+, is pressed.
    static let openSettings = Notification.Name("appShell.openSettings")
    /// Posted with `userInfo["query"]` to pre-seed the palette search field.
    static let palettePrefilter = Notification.Name("appShell.palettePrefilter")
}

// MARK: - KeyboardShortcutsHandler

/// `ViewModifier` applied to the root window content.
///
/// Wires:
/// - `.commands { K8sManagerCommands() }` shortcut declarations.
/// - `.overlay(ToastStackView())` at top-trailing.
/// - `.sheet` for `CommandPaletteOverlay`.
/// - Responds to `NotificationCenter` dispatches from `K8sManagerCommands`.
public struct KeyboardShortcutsHandler: ViewModifier {

    @Binding var selectedFeature: Feature?
    @State private var paletteViewModel: CommandPaletteViewModel
    @State private var toastViewModel: ToastStackViewModel

    public init(
        selectedFeature: Binding<Feature?>,
        paletteViewModel: CommandPaletteViewModel,
        toastViewModel: ToastStackViewModel
    ) {
        self._selectedFeature = selectedFeature
        self._paletteViewModel = State(initialValue: paletteViewModel)
        self._toastViewModel = State(initialValue: toastViewModel)
    }

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                ToastStackView(viewModel: toastViewModel)
            }
            .overlay {
                CommandPaletteOverlay(viewModel: paletteViewModel)
            }
            .onReceive(NotificationCenter.default.publisher(for: .palettePrefilter)) { note in
                let query = note.userInfo?["query"] as? String ?? ""
                paletteViewModel.open(prefiltered: query)
            }
            .onReceive(NotificationCenter.default.publisher(for: .refreshCurrentView)) { _ in
                // Broadcast consumed by individual views via `.onReceive`.
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
                // Broadcast consumed by ResourceBrowserView via `.onReceive`.
            }
    }
}

// MARK: - View extension convenience

public extension View {
    /// Applies `KeyboardShortcutsHandler` to wire palette, toasts, and shortcuts.
    func k8sKeyboardShortcuts(
        selectedFeature: Binding<Feature?>,
        paletteViewModel: CommandPaletteViewModel,
        toastViewModel: ToastStackViewModel
    ) -> some View {
        modifier(KeyboardShortcutsHandler(
            selectedFeature: selectedFeature,
            paletteViewModel: paletteViewModel,
            toastViewModel: toastViewModel
        ))
    }
}
