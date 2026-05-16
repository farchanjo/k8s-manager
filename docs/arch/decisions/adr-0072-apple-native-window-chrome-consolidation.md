# ADR-0072 — Apple-native window chrome consolidation

- Status — Accepted (ratified 2026-05-16)
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none)
- Informed — (none)
- Refines — ADR-0021 (app shell design system and main layout),
  ADR-0051 (multi-cluster workspace: cluster strip, provider grouping, chrome layout),
  ADR-0065 (navigation history stack)
- Amends — ADR-0050 (resource navigation taxonomy + tab system),
  ADR-0051 (multi-cluster workspace),
  ADR-0057 (bottom-docked terminal pane),
  ADR-0064 (inline docked YAML editor pane),
  ADR-0065 (navigation history stack)
- Tags — ui, app-shell, chrome, layout, toolbar, overlay, cluster-strip, status-bar

## Context and problem statement

K8sManager's current app shell stacks the following horizontal faixas (bands) from top to bottom:

1. Window toolbar (title + controls)
2. Canvas header bar (back/forward arrows + global namespace picker)
3. Tab bar (multi-document tabs)
4. Content area (resource list or detail)
5. Docked pane region (inline terminal pane or inline YAML editor pane, when open)
6. Status bar (cluster telemetry — always visible)
7. Cluster strip (vertical strip — always visible at the left edge, occupying its own column)

That is seven distinct chrome zones. The operator feedback collected on 2026-05-16 characterised
this layout as "muito fragmentado" (highly fragmented): every cluster switch or tab navigation
triggers a cascade of simultaneous changes across multiple faixas, creating high visual noise.

The canonical Apple-native reference apps — Mail, Finder, Notes, Xcode, and Numbers — consistently
use a three-band structure: window toolbar, content, optional footer. Research from three independent
sources confirms that this pattern also applies at the Kubernetes tooling layer:

- **kean.blog / Triple Trouble** — argues that the macOS window toolbar is the canonical home for
  navigation controls and persistent secondary affordances; separate "sub-toolbars" inside content
  area break the window chrome contract.
- **msena.com / Three-Column Layout** — documents that `NavigationSplitView` with `.unifiedCompact`
  toolbar style eliminates the visual separation between toolbar and sidebar, giving content more
  vertical breathing room.
- **nilcoalescing.com / macOS Toolbar Styles** — demonstrates that `.windowToolbarStyle(.unifiedCompact)`
  with `showsTitle: false` on the scene produces the tightest possible top chrome, identical to
  Finder's toolbar style on macOS 14+.

The user (Fabricio Fonseca) explicitly authorised a "Full reset (#1-6, alto risco)" on 2026-05-16,
covering all six consolidation changes. ADR-0073 addresses change #6 (Inspector trailing column)
separately. This ADR addresses changes #1–5.

## Decision drivers

- **Fewer faixas** — canonical Apple HIG apps use at most three horizontal bands; K8sManager must
  not exceed this without a documented justification per band.
- **Breathing room** — each eliminated chrome band returns vertical pixels to the content area, the
  resource list where operators spend the most time.
- **Reduced visual transitions** — docked panes that steal canvas height cause layout shifts on every
  open/close. Overlay sheets that float over content eliminate the layout shift entirely.
- **Apple HIG conformance** — `.unifiedCompact` toolbar style is the Apple-recommended style for
  utility and productivity applications on macOS 14+.
- **Persistence contract** — any new visibility toggle added to window chrome must persist its state
  across launches so the operator's preference survives application restart.

## Considered options

- **Option A** — Keep current 7-band shell (no change).
- **Option B** — Partial consolidation: move namespace pill to toolbar (already done, ADR-0069) but
  leave docked panes, status bar, and cluster strip unchanged.
- **Option C** — Full reset: collapse to 3 bands via the 5 targeted changes below. (chosen)

## Decision outcome

Chosen option — **Option C**, because:

- Option A preserves a layout that the operator explicitly described as fragmented and rejected.
- Option B addresses only the namespace pill (already shipped in ADR-0069) and leaves the remaining
  five pain points untouched.
- Option C aligns with all three cited external sources, conforms to Apple HIG, and was explicitly
  authorised by the project owner on 2026-05-16.

The outcome is a window chrome with exactly three horizontal bands:

```
+-----------------------------------------------------------+
| Window toolbar (.unifiedCompact, no title)               |  Band 1
|  [⬅ ➡] [cluster avatar + toggle] … [ns pill] [⌘⇧A] [🔔] |
+-----------------------------------------------------------+
| Tab bar (below toolbar, above content)                   |  (part of Band 2)
+-----------------------------------------------------------+
| Content area (resource list / inspector / overview)      |  Band 2
|                                                          |
|   ╔══════════════════════════════════════╗  ← overlay    |
|   ║  Terminal / YAML editor pane         ║   sheet       |
|   ║  (slides up from bottom of Band 2)  ║               |
|   ╚══════════════════════════════════════╝               |
+-----------------------------------------------------------+
| Status footer (rendered only when toasts are present)    |  Band 3 (optional)
+-----------------------------------------------------------+
```

### Change 1 — Window toolbar style: `.unifiedCompact` + no title

**Old behaviour** — The scene uses the default `WindowGroup` toolbar style, which renders a title
bar row (showing "K8sManager" or the active cluster name) above a separate toolbar row. Two distinct
sub-rows are visible at the top of every window. The toolbar style is unspecified in code; it
defaults to `.automatic`, which on macOS renders as `.expanded` for document-based windows.

Relevant current call site (stub — implementation will fill exact line on landing):
`Sources/AppShell/Scene/K8sManagerRootScene.swift` — `WindowGroup` scene body.

**New behaviour** — The scene modifier chain adds:

```swift
.windowStyle(.hiddenTitleBar)
.windowToolbarStyle(.unifiedCompact(showsTitle: false))
```

The window title is suppressed. The toolbar and title bar merge into a single compact row. The
`NavigationSplitView` sidebar column header no longer shows a redundant title.

**Migration mechanic** — Applied at the `WindowGroup` scene level in `K8sManagerRootScene.swift`.
No view-level changes are required; `.unifiedCompact` is a scene-level concern.

**Invariant established** — The app shell may never render more than one toolbar row at the top of
the primary window. Any `ToolbarItem` that does not fit in the `.unifiedCompact` row must use the
overflow menu (`...`); it may not introduce a secondary toolbar row.

### Change 2 — Nav arrows move to window toolbar `.navigation` placement

**Old behaviour** — Back (`chevron.backward`) and forward (`chevron.forward`) arrows are rendered
inside `SidebarCanvasView.headerBar`, a custom `HStack` placed at the top of the content column,
below the window toolbar and above the tab bar. The `headerBar` is defined in:

`Sources/AppShell/Views/Sidebar/SidebarCanvasView.swift` (stub line — see above).

The `headerBar` VStack occupies approximately 36 pt of vertical height. Its sole remaining contents
after ADR-0069 removed `GlobalNamespacePicker` are these two arrow buttons plus a `Spacer`.

**New behaviour** — The two arrow buttons are promoted to the window toolbar using the SwiftUI
`.navigation` placement:

```swift
ToolbarItem(placement: .navigation) {
    Button(action: { Task { await historyActor.back() } }) {
        Label("Navigate back", systemImage: "chevron.backward")
    }
    .disabled(!canGoBack)
}
ToolbarItem(placement: .navigation) {
    Button(action: { Task { await historyActor.forward() } }) {
        Label("Navigate forward", systemImage: "chevron.forward")
    }
    .disabled(!canGoForward)
}
```

`SidebarCanvasView.headerBar` is removed entirely. The `SidebarCanvasView` body is simplified to a
`VStack` containing the tab bar row and the content area only.

**Migration mechanic** — Remove `headerBar` from `SidebarCanvasView.swift`. Add two `ToolbarItem`
declarations (placement `.navigation`) in the primary content view's `.toolbar { }` block, wired to
`NavigationHistoryActor` (ADR-0065).

**Invariant established** — Navigation history controls (back/forward) live exclusively in the
window toolbar `.navigation` slot. No view inside the content column may render its own
back/forward affordance.

### Change 3 — Status bar renders conditionally (toasts only)

**Old behaviour** — `StatusBarView` is unconditionally rendered at the bottom of the primary
`AppShell` composition stack, occupying approximately 28 pt of vertical height at all times. It
shows cluster display name, Kubernetes version, CPU/Mem aggregate, watch stream count, and error
badge (ADR-0051 §Status bar).

Relevant current call site (stub):
`Sources/AppShell/Views/AppShellContentView.swift` — the outer `VStack` that stacks the
`NavigationSplitView` above `StatusBarView`.

**New behaviour** — `StatusBarView` is conditionally rendered only when one or more toast
notifications are currently active. The render condition is:

```swift
if !toastQueue.isEmpty {
    StatusBarView(toasts: toastQueue)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: toastQueue.isEmpty)
}
```

The persistent cluster telemetry fields (cluster name, Kubernetes version, CPU/Mem, watch count)
previously shown in the status bar are migrated as follows:

- **Cluster name + provider icon** — already present in the window toolbar via the cluster avatar
  chip in Change 4 (see below).
- **Kubernetes version** — moved to the cluster avatar chip tooltip (hover).
- **CPU/Mem aggregate + watch stream count** — moved to the `ClusterStripView` chip row tooltip
  (hover over the active cluster avatar).
- **Error count badge** — moved to the `NotificationsButton` badge in the top-right chrome
  (already present per ADR-0051 §Top-right chrome).

**Migration mechanic** — Wrap the `StatusBarView` call site in a conditional block driven by
`ToastQueueActor.isPresenting` (a `Bool` property already exposed by `ToastQueueActor` per
ADR-0032). Remove the unconditional `StatusBarView` from the outer `VStack`.

**Invariant established** — The status bar footer occupies zero height when no toasts are queued.
Cluster telemetry is always accessible via hover tooltips on the cluster avatar and cluster strip
chips; it does not require a dedicated persistent footer.

### Change 4 — ClusterStripView becomes operator-toggleable

**Old behaviour** — `ClusterStripView` is always visible at the left edge of the window frame,
outside the `NavigationSplitView`, occupying a fixed 52 pt column (ADR-0051 §Vertical cluster
strip, "It is always visible; it cannot be collapsed.").

Relevant current call site (stub):
`Sources/AppShell/Views/AppShellContentView.swift` — the `HStack` that places `ClusterStripView`
to the left of `NavigationSplitView`.

**New behaviour** — `ClusterStripView` visibility is toggled by a window-toolbar button:

```swift
ToolbarItem(placement: .primaryAction) {
    Button(action: { layoutState.clusterStripVisible.toggle() }) {
        Label("Toggle Cluster Strip",
              systemImage: layoutState.clusterStripVisible ? "sidebar.left" : "sidebar.left")
    }
}
```

Default state: visible (`clusterStripVisible = true`). The operator can collapse the strip to
reclaim 52 pt of horizontal space for the content area.

**Persistence schema migration** — `WindowLayout.mainWindow` gains a new field:

```
clusterStripVisible: bool (default: true)
```

The field is added to `contexts/app_shell/schemas/window_layout.cue` under `#MainWindowLayout`.
The schema version is bumped from whatever the current version is to the next patch increment. On
first launch after the migration, the field defaults to `true` if absent (backwards compatible).

When `clusterStripVisible == false`, the active cluster context is still accessible via:

- The cluster avatar rendered in the window toolbar (left of the nav arrows), showing the active
  cluster initials + status ring — a new `ToolbarItem(placement: .navigation)` added by this change.
- The keyboard shortcut `⌘⇧K` to toggle the strip back to visible.

**Migration mechanic** — Wrap the `ClusterStripView` call site in an `if layoutState.clusterStripVisible`
conditional. Add the toolbar toggle `ToolbarItem` and the compact cluster avatar `ToolbarItem` in
the primary window's `.toolbar { }` block. Update `WindowLayout` CUE schema.

**Invariant established** — `ClusterStripView` is never unconditionally rendered. Its visibility is
always a function of `WindowLayout.mainWindow.clusterStripVisible`. The active cluster context
remains accessible from the window toolbar regardless of strip visibility.

### Change 5 — Docked panes become bottom-sheet overlays

**Old behaviour** — `DockedTerminalPane` (ADR-0057) and `DockedYAMLEditorPane` (ADR-0064) are
rendered as inline members of the content-area `VStack`, below the resource list and above the
status bar. When open, each pane steals height from the resource list, causing a layout shift of up
to 40% of the content area height. Only one pane can be visible at a time (ADR-0064
§Coexistence rules).

Relevant current call site (stub):
`Sources/AppShell/Views/AppShellContentView.swift` — `dockedPaneRegion` within the outer `VStack`.

**New behaviour** — Both panes are rendered as floating overlay sheets anchored to the bottom of the
content area column:

```swift
contentAreaView
    .overlay(alignment: .bottom) {
        if terminalPaneState.isVisible {
            DockedTerminalPaneView()
                .frame(maxHeight: contentAreaHeight * 0.5)
                .transition(.move(edge: .bottom))
        }
    }
    .overlay(alignment: .bottom) {
        if yamlEditorPaneState.isVisible {
            DockedYAMLEditorPaneView()
                .frame(maxHeight: contentAreaHeight * 0.5)
                .transition(.move(edge: .bottom))
        }
    }
```

The overlay floats over the content area — the resource list is not displaced. The pane obscures
the lower portion of the list but does not resize the list above it. The operator can scroll the
list to bring rows above the overlay fold.

Maximum overlay height: 50% of the content area height (down from 80% for the terminal pane in
ADR-0057). The operator can drag-resize within the 50% cap using the existing drag-resize handle.
Mutual exclusion (terminal XOR YAML visible) is unchanged from ADR-0064 §Coexistence rules.

**Migration mechanic** — Remove the `dockedPaneRegion` from the `VStack` in `AppShellContentView`.
Apply `.overlay(alignment: .bottom)` modifier chain on the content area view. Update the max-height
constraint in `DockedTerminalPaneView` and `DockedYAMLEditorPaneView` from `80% contentArea` and
`contentArea - 120 pt` respectively to `50% contentArea` for both.

The `DockedTerminalPane` actor and `DockedEditorPaneOrchestrator` application service (ADR-0057,
ADR-0064) are unaffected — this is a presentation-layer change only.

**Invariant established** — No docked pane may ever resize the resource list or content area above
it. Panes are always floating overlays. The content area height is a constant for the lifetime of
the window; it changes only when the window is resized by the operator.

## Pros and cons of the options

### Option A — Keep current 7-band shell

- Good, because zero migration risk; existing behaviour is fully tested.
- Bad, because the operator explicitly rejected it as "muito fragmentado".
- Bad, because it diverges from Apple HIG and the three external research sources.
- Bad, because layout shifts on docked-pane open/close create regression risk on every new view.

### Option B — Partial consolidation (namespace pill only)

- Good, because the namespace pill migration (ADR-0069) already shipped; no additional risk.
- Bad, because five of the six identified pain points remain unaddressed.
- Bad, because the headerBar (now empty after ADR-0069) is retained purely to keep nav arrows
  in place — which is wasteful and aesthetically inconsistent.

### Option C — Full reset (chosen)

- Good, because all five changes are compositionally independent and can be delivered in a single
  wave without cross-dependency risk.
- Good, because `.unifiedCompact` and overlay panes are well-documented SwiftUI primitives with no
  third-party dependency.
- Good, because the operator authorised the full reset explicitly.
- Bad, because the `WindowLayout` schema requires a version bump and migration path.
- Bad, because `ClusterStripView` hidden by default removes one-click cluster switching (mitigated
  by the compact cluster avatar in the toolbar and the `⌘⇧K` shortcut).

## Confirmation

The following file paths are stubs; exact line numbers are filled by the implementation wave.

- `Sources/AppShell/Scene/K8sManagerRootScene.swift` — adds `.windowStyle(.hiddenTitleBar)` and
  `.windowToolbarStyle(.unifiedCompact(showsTitle: false))` to the `WindowGroup` modifier chain.
- `Sources/AppShell/Views/Sidebar/SidebarCanvasView.swift` — `headerBar` computed property removed;
  nav arrows removed from this file.
- `Sources/AppShell/Views/Toolbar/NavigationArrowsToolbarItems.swift` — new file; two `ToolbarItem`
  declarations wired to `NavigationHistoryActor`.
- `Sources/AppShell/Views/AppShellContentView.swift` — `StatusBarView` wrapped in
  `if !toastQueue.isEmpty`; `ClusterStripView` wrapped in `if layoutState.clusterStripVisible`;
  `dockedPaneRegion` replaced by two `.overlay(alignment: .bottom)` modifiers.
- `Sources/AppShell/Views/Toolbar/ClusterStripToggleToolbarItem.swift` — new file; toolbar toggle
  button for the cluster strip.
- `Sources/AppShell/Views/Toolbar/ActiveClusterAvatarToolbarItem.swift` — new file; compact cluster
  avatar shown in toolbar when strip is hidden.
- `contexts/app_shell/schemas/window_layout.cue` — `#MainWindowLayout` gains
  `clusterStripVisible: bool` field; schema version bumped.
- `Tests/AppShellTests/WindowChromeConsolidationTests.swift` — snapshot tests for each of the
  five states: toolbar-only nav arrows, status bar hidden, status bar with toast, cluster strip
  visible, cluster strip hidden.

## More information

- ADR-0021 — App shell design system; original `NavigationSplitView` layout baseline.
- ADR-0032 — Toast notification system; `ToastQueueActor.isPresenting` used by Change 3.
- ADR-0050 — Resource navigation taxonomy + tab system; amended by this ADR.
- ADR-0051 — Multi-cluster workspace; amended by this ADR (cluster strip toggleable).
- ADR-0057 — Bottom-docked terminal pane; amended by this ADR (overlay sheet).
- ADR-0064 — Inline docked YAML editor pane; amended by this ADR (overlay sheet).
- ADR-0065 — Navigation history stack; amended by this ADR (arrows move to toolbar).
- ADR-0069 — Global namespace pill in toolbar; live in the toolbar row extended here.
- ADR-0070 — Sidebar selection and tab sync; invariant unchanged; source of truth remains
  `OpenTabsActor`.
- ADR-0073 — Inspector trailing column; the companion ADR covering Change 6 (Inspector).

## Amendments

*(This section will be appended by future ADRs that refine this decision.)*
