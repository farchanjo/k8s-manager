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

    /// Mirrors `AppShellView.clusterStripVisible` via shared `@AppStorage` key.
    ///
    /// SwiftUI shares `@AppStorage` across views using the same key so both
    /// the Commands graph and the view tree read and write the same persisted
    /// flag without prop-drilling (ADR-0074 Change C).
    @AppStorage("appShell.clusterStripVisible") private var clusterStripVisible = true

    public init(
        isPaletteVisible: Binding<Bool>,
        selectedFeature: Binding<Feature?>
    ) {
        self._isPaletteVisible = isPaletteVisible
        self._selectedFeature = selectedFeature
    }

    public var body: some Commands {
        CommandMenu("Navigate") {
            // ⌘[ — navigate back (ADR-0065)
            Button("Back") {
                NotificationCenter.default.post(name: .k8sManagerNavigateBack, object: nil)
            }
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityLabel("Navigate back")

            // ⌘] — navigate forward (ADR-0065)
            Button("Forward") {
                NotificationCenter.default.post(name: .k8sManagerNavigateForward, object: nil)
            }
            .keyboardShortcut("]", modifiers: .command)
            .accessibilityLabel("Navigate forward")

            Divider()

            // ⌘K — toggle palette (primary activation per ADR-0023)
            Button("Command Palette") {
                NotificationCenter.default.post(name: .k8sManagerOpenPalette, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)
            .accessibilityLabel("Toggle command palette")

            // ⌘P — palette alternate activation
            Button("Search Commands") {
                NotificationCenter.default.post(name: .k8sManagerOpenPalette, object: nil)
            }
            .keyboardShortcut("p", modifiers: .command)
            .accessibilityLabel("Open command palette")

            Divider()

            // ⌘⇧W — focus the persistent workspace Welcome tab (ADR-0054)
            Button("Go to Welcome Tab") {
                NotificationCenter.default.post(name: .k8sManagerFocusWelcomeTab, object: nil)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .accessibilityLabel("Focus the Welcome tab")

            // ⌘⇧C — switch context via palette pre-filtered
            Button("Switch Context…") {
                NotificationCenter.default.post(
                    name: .palettePrefilter,
                    object: nil,
                    userInfo: ["query": "switch context"]
                )
                NotificationCenter.default.post(name: .k8sManagerOpenPalette, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .accessibilityLabel("Switch Kubernetes context")

            // ⌘1–⌘9 — jump to sidebar feature by index (0-based Feature.allCases)
            ForEach(Feature.allCases.prefix(9).indices, id: \.self) { index in
                let feature = Feature.allCases[index]
                Button("Jump to \(feature.title)") {
                    NotificationCenter.default.post(
                        name: .k8sManagerJumpToFeature,
                        object: nil,
                        userInfo: ["feature": feature.rawValue]
                    )
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
                NotificationCenter.default.post(name: .k8sManagerRefresh, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel("Refresh current view")
        }

        CommandMenu("View") {
            // ⌘⇧K — toggle cluster-strip column (ADR-0074 Change C).
            // Moved from the window toolbar into the View menu so the toolbar
            // stays within the ≤7 item HIG ceiling. The cluster strip and the
            // NavigationSplitView sidebar are deliberately independent toggles:
            // cluster strip = cross-cluster selector; sidebar = per-cluster
            // resource tree (see Change F comments in AppShell.swift).
            Button(clusterStripVisible ? "Hide Cluster Strip" : "Show Cluster Strip") {
                clusterStripVisible.toggle()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .accessibilityLabel(clusterStripVisible
                ? "Hide cluster strip column"
                : "Show cluster strip column")
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

        // ⌘\ — toggle assistant slide-out panel (ADR-0051)
        CommandGroup(after: .toolbar) {
            Button("Toggle Assistant") {
                NotificationCenter.default.post(name: .k8sManagerToggleAssistant, object: nil)
            }
            .keyboardShortcut("\\", modifiers: .command)
            .accessibilityLabel("Toggle PRISM AI assistant panel")

            // ⌘N — toggle notifications (ADR-0051)
            Button("Toggle Notifications") {
                NotificationCenter.default.post(name: .k8sManagerToggleNotifications, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel("Toggle notifications panel")

            // ⌃` — toggle docked terminal pane (ADR-0057)
            Button("Toggle Terminal Pane") {
                NotificationCenter.default.post(name: .k8sManagerToggleTerminalPane, object: nil)
            }
            .keyboardShortcut("`", modifiers: .control)
            .accessibilityLabel("Toggle bottom-docked terminal pane")

            // ⌥E — toggle docked YAML editor pane (ADR-0064)
            Button("Toggle YAML Editor Pane") {
                NotificationCenter.default.post(name: .k8sManagerToggleYAMLEditorPane, object: nil)
            }
            .keyboardShortcut("e", modifiers: .option)
            .accessibilityLabel("Toggle inline docked YAML editor pane")

            // ⌘⌥0 — toggle Inspector trailing column (ADR-0073).
            // Matches Xcode's Attributes inspector toggle shortcut.
            Button("Toggle Inspector") {
                NotificationCenter.default.post(name: .k8sManagerToggleInspector, object: nil)
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .accessibilityLabel("Toggle resource inspector panel")
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
    /// Posted by the command palette when the user selects a context-switch entry.
    static let k8sManagerSwitchContext = Notification.Name("appShell.switchContext")
    /// Posted by the command palette to trigger a resource refresh.
    static let k8sManagerRefresh = Notification.Name("appShell.refresh")
    /// Posted to bring the command palette into view.
    static let k8sManagerOpenPalette = Notification.Name("appShell.openPalette")
    /// Posted by ⌘1–⌘9. `userInfo`: `["feature": String]` matching `Feature.rawValue`.
    static let k8sManagerJumpToFeature = Notification.Name("appShell.jumpToFeature")
    /// Posted by ⌘⇧W or the command palette "Go to Welcome tab" entry — the
    /// workspace tabs actor subscribes and focuses the persistent Welcome tab.
    static let k8sManagerFocusWelcomeTab = Notification.Name("appShell.focusWelcomeTab")
    /// Posted when ⌘[ is pressed — `NavigationHistoryActor` subscriber calls `back()`.
    static let k8sManagerNavigateBack = Notification.Name("appShell.navigateBack")
    /// Posted when ⌘] is pressed — `NavigationHistoryActor` subscriber calls `forward()`.
    static let k8sManagerNavigateForward = Notification.Name("appShell.navigateForward")
    /// Posted when `⌃\`` is pressed — `SidebarCanvasView` toggles the docked terminal pane
    /// (ADR-0057).
    static let k8sManagerToggleTerminalPane = Notification.Name("appShell.toggleTerminalPane")
    /// Posted when `⌥E` is pressed — `SidebarCanvasView` toggles the docked YAML editor pane
    /// (ADR-0064).
    static let k8sManagerToggleYAMLEditorPane = Notification.Name("appShell.toggleYAMLEditorPane")
    /// Posted when `⌘⌥0` is pressed — `AppShellView` calls `inspectorViewModel.toggle()`
    /// (ADR-0073). Matches Xcode's Attributes inspector toggle shortcut.
    static let k8sManagerToggleInspector = Notification.Name("appShell.toggleInspector")
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
            // ⌘K / ⌘P — toggle palette
            .onReceive(NotificationCenter.default.publisher(for: .k8sManagerOpenPalette)) { _ in
                if paletteViewModel.isVisible {
                    paletteViewModel.dismiss()
                } else {
                    paletteViewModel.open()
                }
            }
            // Palette pre-filter seed (⌘⇧C or tray "Switch Context…" button)
            .onReceive(NotificationCenter.default.publisher(for: .palettePrefilter)) { note in
                let query = note.userInfo?["query"] as? String ?? ""
                paletteViewModel.open(prefiltered: query)
            }
            // Context-switch palette command → navigate to Contexts feature
            .onReceive(NotificationCenter.default.publisher(for: .k8sManagerSwitchContext)) { _ in
                selectedFeature = .contexts
            }
            // ⌘R → re-broadcast so the active feature view refreshes
            .onReceive(NotificationCenter.default.publisher(for: .k8sManagerRefresh)) { _ in
                NotificationCenter.default.post(name: .refreshCurrentView, object: nil)
            }
            // ⌘1–⌘9 → jump to feature
            .onReceive(NotificationCenter.default.publisher(for: .k8sManagerJumpToFeature)) { note in
                guard let raw = note.userInfo?["feature"] as? String,
                      let feature = Feature(rawValue: raw) else { return }
                selectedFeature = feature
            }
            // ⌘L — focus search (forwarded; consumed by ResourceBrowserView)
            .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in }
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
