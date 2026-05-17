# ADR-0074 — Apple HIG toolbar header consolidation

- Status — Accepted (ratified 2026-05-16)
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none)
- Informed — (none)
- Refines — ADR-0021 (app shell design system and main layout),
  ADR-0051 (multi-cluster workspace: top-right chrome contract),
  ADR-0069 (global namespace pill in top-right chrome toolbar),
  ADR-0072 (Apple-native window chrome consolidation),
  ADR-0073 (Inspector trailing column)
- Tags — ui, app-shell, chrome, toolbar, hig, namespace-pill, inspector, export, assistant

## Context and problem statement

Following the chrome-consolidation wave delivered in ADR-0072 and ADR-0073, an operator screenshot
of the running build revealed that the unified window toolbar still carries eight interactive items:

```
[<>] [▢ cluster-strip] [▢ inspector] [All namespaces ⌄] [⌄ ↻] [✨ PRISM AI] [🔔] [FA] [⊘ export]
```

Each individual item was justified at the time of its ADR, but no ADR has governed the toolbar as
a whole. The result is visual cacophony: mixed icon-only and icon+text buttons, a wider-than-needed
namespace pill, two independent sidebar toggles, and an export affordance that belongs in a context
menu rather than a persistent toolbar slot.

Apple's canonical productivity applications — Mail, Notes, Xcode, Numbers, and Finder — hold to a
ceiling of five to seven toolbar items in the icon-only style with tooltips, with clear leading and
trailing separation. ADR-0021 §"Toolbar and sidebar conventions" states that the toolbar should be
"visually calm with uniform icon-only buttons". That invariant has been eroded by successive
additive changes without a governing ceiling.

Multiple ADRs have each contributed one chrome element without an orchestrating constraint:

- ADR-0051 — top-right chrome: assistant toggle, notifications, avatar.
- ADR-0069 — namespace pill (180–220 pt) in the chrome row.
- ADR-0072 — cluster-strip toggle and inspector toggle added to the toolbar.
- ADR-0073 — inspector toggle placement defined as `.primaryAction` before `TopRightChrome`.

This ADR enforces a toolbar ceiling of five trailing items plus two leading items (seven total) and
delivers six targeted changes — labelled Change A through Change F — that bring the toolbar within
that ceiling and restore the icon-only visual language.

## Decision drivers

- **Apple HIG toolbar ceiling** — canonical productivity apps hold to five to seven toolbar items;
  K8sManager must not exceed seven without a new ADR and explicit ratification.
- **Icon-only uniform style** — the ADR-0021 design-system invariant requires chrome controls to
  be visually calm with uniform icon-only buttons and tooltips; mixed icon+text buttons violate it.
- **Discoverable export** — the right-click context menu is the macOS-canonical location for row
  actions including export; a persistent toolbar slot for export wastes chrome real estate.
- **Inspector position** — WWDC23 "Inspectors in SwiftUI" places the inspector toggle at the
  rightmost toolbar edge (far trailing); the current placement before `TopRightChrome` puts it
  adjacent to the namespace pill, violating the WWDC23 canonical pattern.
- **Single sidebar toggle** — two separate toolbar buttons for the sidebar tree and the cluster
  strip create ambiguity; the `NavigationSplitView` built-in sidebar toggle already controls the
  sidebar tree; the cluster-strip toggle is the power-user override, not the primary toggle.
- **Namespace pill compactness** — the 180–220 pt pill width is wider than required for the
  "default" label (the most common value); narrowing it to 140–180 pt recovers horizontal space
  without losing legibility.

## Considered options

- **Option A** — All six changes shipped together. Full toolbar reset to the HIG ceiling. (chosen)
- **Option B** — Demote PRISM AI text, compact the namespace pill, and move the inspector to the
  far trailing edge. Defer toggle consolidation and export relocation. Smaller blast radius but
  leaves the toolbar count at seven to eight items and the export affordance unreformed.
- **Option C** — Add a "Toolbar density" preference toggle. Let operators choose compact or
  expanded presentation. Pushes the default-presentation problem to operator config; does not fix
  the out-of-the-box experience and introduces a preference knob with no clear default policy.

## Decision outcome

Chosen option — **Option A**, because:

- Option B partially addresses the visual problem but does not bring the toolbar within the HIG
  ceiling; the cluster-strip toggle and export button remain unresolved.
- Option C delegates a design decision to the operator. Apple HIG guidance is that toolbars should
  be sensible out of the box; preferences are for personalisation, not for correcting defaults.
- Option A was explicitly operator-authorized on 2026-05-16 as a full toolbar reset and is the
  only option that satisfies the HIG ceiling invariant without residual debt.

### Toolbar ceiling invariant

The window toolbar after this ADR contains exactly seven interactive items:

```
LEADING:   [<>] [sidebar-toggle]                                      — 2 items
TRAILING:  [namespace-pill] [assistant] [bell] [avatar] [inspector]   — 5 items
```

Future toolbar additions require a new ADR ratified by the deciders. No `ToolbarItem` may be
added to the primary window toolbar without updating the ceiling invariant documented here.

### Change A — AssistantToggleButton icon-only

**Old behaviour** — `AssistantToggleButton` renders a `Label` with `sparkles` SF Symbol and the
text "PRISM AI" plus a filled capsule background, making it the only chrome button with a visible
text label and a background fill. Width is approximately 100–110 pt.

Relevant file (stub — implementation fills exact lines):
`Sources/AppShell/Views/Chrome/AssistantToggleButton.swift`

**New behaviour** — The button is reduced to icon-only (`systemImage: "sparkles"`, no title
string, no background fill). It matches the visual density of `NotificationsButton` and the user
avatar button. The tooltip retains the full label: "PRISM AI (⌘\\)".

```swift
Button(action: { assistantVisible.toggle() }) {
    Image(systemName: "sparkles")
}
.help("PRISM AI (⌘\\)")
```

The keyboard shortcut `⌘\` is unchanged. The assistant menu-bar entry retains its full text label.

**Invariant established** — `AssistantToggleButton` is icon-only in all toolbar contexts. Any
future iteration that adds a text label or background fill to the toolbar button requires a toolbar
ceiling review.

### Change B — GlobalNamespacePill compact

**Old behaviour** — `GlobalNamespacePill` has a fixed width of 180–220 pt (ADR-0069 §"Pill
shape"). When no namespace is selected, the label reads "All namespaces". The wide frame is
reserved for long namespace names but wastes space for the common "default" case.

Relevant file (stub — implementation fills exact lines):
`Sources/AppShell/Views/Chrome/GlobalNamespacePill.swift`

**New behaviour** — The pill width narrows to 140–180 pt. The default label when `selection == nil`
changes to "default" when `NamespaceFilterActor.current(for:)` returns `nil` (no active filter).
"All namespaces" is retained as a menu choice label only, not as the persistent pill label.

The `Color.clear.frame(width: 200, height: 32)` placeholder used when `activeClusterId == nil`
(ADR-0069 §GlobalNamespacePill) is reduced to `Color.clear.frame(width: 160, height: 32)` to
match the narrowed width.

**ADR-0069 §"Pill shape" is amended** — the pill width floor is 140 pt, ceiling is 180 pt.
"All namespaces" is a menu item label; the resting pill label is "default" (no active filter)
or the namespace name (active filter).

### Change C — Cluster-strip toggle moves to View menu

**Old behaviour** — ADR-0072 §"Change 4" adds a `ToolbarItem(placement: .primaryAction)` to the
primary window toolbar to toggle `ClusterStripView` visibility. This occupies one toolbar slot and
sits adjacent to the inspector toggle, making two sidebar-related toggles visible simultaneously.

Relevant file (stub — implementation fills exact lines):
`Sources/AppShell/AppShell.swift`

**New behaviour** — The cluster-strip toggle `ToolbarItem` is removed from the toolbar entirely.
The toggle is exposed via `K8sManagerCommands` as a View menu item:

```
View
  Show Cluster Strip    ⌘⇧K  (checkmark when visible)
```

The keyboard shortcut `⌘⇧K` is preserved. `ClusterStripView` visibility continues to be driven by
`WindowLayout.mainWindow.clusterStripVisible` (defined in ADR-0072). The compact cluster avatar
`ToolbarItem` introduced in ADR-0072 §"Change 4" (shown when the strip is hidden) is also moved
out of the toolbar; the cluster avatar is instead rendered inside the `NavigationSplitView` sidebar
header when the strip is hidden.

**ADR-0072 §"Change 4" is amended** — the cluster-strip toolbar toggle button is replaced by a
View menu item. The keyboard shortcut `⌘⇧K` remains. Strip visibility semantics and the
`WindowLayout` field are unchanged.

### Change D — Inspector toggle moves to far-trailing edge

**Old behaviour** — ADR-0073 §"Inspector visibility" places the inspector toggle as a
`ToolbarItem(placement: .inspector)`. However, in the composed toolbar the inspector toggle item
renders before `TopRightChrome` due to declaration order in `AppShell.swift`. On macOS, toolbar
items are packed in declaration order in the primary action area; this places the inspector toggle
adjacent to the namespace pill rather than at the rightmost edge.

Relevant file (stub — implementation fills exact lines):
`Sources/AppShell/AppShell.swift`

**New behaviour** — The inspector toggle `ToolbarItem` is declared after all `TopRightChrome`
items in the `.toolbar { }` block. Because macOS respects declaration order within the primary
action group, the inspector toggle lands at the rightmost edge of the toolbar — the WWDC23
canonical position for inspector toggles in `NavigationSplitView`-based applications.

The icon differentiates open and closed states:

```swift
ToolbarItem(placement: .primaryAction) {
    Button(action: { inspectorVisible.toggle() }) {
        Image(systemName: inspectorVisible ? "sidebar.trailing.fill" : "sidebar.trailing")
    }
    .help(inspectorVisible ? "Hide Inspector (⌘⌥0)" : "Show Inspector (⌘⌥0)")
}
```

**ADR-0073 §"Inspector visibility" is amended** — the inspector toggle `ToolbarItem` is declared
last in the toolbar block (after `TopRightChrome`) so it lands at the far trailing edge. Icon
differentiates states: `sidebar.trailing.fill` (open) vs `sidebar.trailing` (closed).

### Change E — ExportMenu moves to RowActionMenu

**Old behaviour** — `ExportMenuContainer`, a view modifier, injects an `ExportMenu` into the
window toolbar via `.toolbar { }` on every resource list view. Fifteen list view files carry this
modifier. The export button (`systemImage: "square.and.arrow.up"`) is permanently visible in the
toolbar for all resource lists, consuming one toolbar slot for an infrequent operation.

Relevant files (stubs — implementation fills exact lines):
`Sources/AppShell/Views/Resources/ExportMenu.swift`
`Sources/AppShell/Views/Resources/RowActionMenu.swift`

**New behaviour** — `ExportMenuContainer` drops its `.toolbar { }` injection across all fifteen
list views. Export becomes a submenu in `RowActionMenu` under a dedicated "Export…" item:

```
Right-click row
  ───────────────
  Edit…            ⌘E
  Delete…          ⌘⌫
  Open in Tab      ⌘T
  ───────────────
  Export…
    Export as CSV
    Export as YAML
    Export as JSON
```

The export operations act on the selected row (or the right-clicked row if selection differs).
The `ExportMenu` view is retained as the submenu content; only its toolbar injection mechanism
is removed.

**Invariant established** — Export is a row action. No resource list view may inject an export
toolbar button. Export is always accessible via `RowActionMenu`.

### Change F — Single sidebar toggle

**Old behaviour** — The `NavigationSplitView` built-in sidebar toggle (keyboard shortcut
`⌘⌃S` on macOS) controls the sidebar tree column. The cluster-strip toggle button (before Change C
removes it from the toolbar) controls `ClusterStripView` independently. The operator faces two
distinct sidebar-related toggle affordances.

Relevant file (stub — implementation fills exact lines):
`Sources/AppShell/AppShell.swift`

**New behaviour** — The `NavigationSplitView` built-in sidebar toggle (`⌘⌃S`) is wired to a
custom callback (`columnVisibilityChanged`) that additionally sets
`WindowLayout.mainWindow.clusterStripVisible` to match the sidebar column visibility. When the
operator hides the sidebar tree, the cluster strip hides simultaneously. When the operator shows
the sidebar tree, the cluster strip shows simultaneously.

The independent cluster-strip toggle is preserved as View menu `⌘⇧K` (Change C) for power users
who need the strip visible without the sidebar tree.

```swift
NavigationSplitView(columnVisibility: $columnVisibility) {
    SidebarView()
} content: {
    ContentView()
}
.onChange(of: columnVisibility) { _, new in
    layoutState.clusterStripVisible = (new != .detailOnly)
}
```

**Invariant established** — The built-in `NavigationSplitView` sidebar toggle is the primary
affordance for showing and hiding the left-side navigation chrome (sidebar tree + cluster strip).
The `⌘⇧K` shortcut provides independent cluster-strip control for power users.

## Pros and cons of the options

### Option A — Full toolbar reset (chosen)

- Good, because the toolbar lands within the Apple HIG ceiling (seven items) from the first
  launch; no preference toggle required.
- Good, because all six changes are compositionally independent and can be delivered in a single
  wave.
- Good, because export moves to a discoverable right-click location, consistent with macOS
  Finder, Mail, and Xcode patterns.
- Good, because inspector toggle at the far-trailing edge follows the WWDC23 canonical pattern.
- Bad, because operators with muscle memory for the "PRISM AI" text label lose the text
  affordance (mitigated by the tooltip and the `⌘\` shortcut).
- Bad, because the cluster-strip toggle moves to the View menu (one more click for occasional
  users; mitigated by `⌘⇧K`).
- Bad, because the export toolbar button is removed (mitigated by the `RowActionMenu`
  Export… submenu, visible on every row right-click).

### Option B — Partial changes only

- Good, because smaller blast radius — fewer view files affected.
- Bad, because the toolbar still carries seven to eight items after the partial changes; the
  ceiling invariant is not satisfied.
- Bad, because the export toolbar button remains, keeping the toolbar item count one over the
  ceiling when combined with the remaining items.

### Option C — Toolbar density preference

- Good, because no existing affordance is removed; operators retain full toolbar item access in
  the "expanded" mode.
- Bad, because the default presentation still violates the Apple HIG ceiling.
- Bad, because it introduces a preference knob that is a workaround for a design problem rather
  than a solution.
- Bad, because it doubles the surface under test: every toolbar layout change must be verified
  in both density modes.

## Confirmation

The following file paths are stubs; exact line numbers are filled by the implementation wave.

- `Sources/AppShell/Views/Chrome/AssistantToggleButton.swift` — icon-only mode; text label and
  background fill removed; tooltip set to "PRISM AI (⌘\\)".
- `Sources/AppShell/Views/Chrome/GlobalNamespacePill.swift` — frame narrowed to 140–180 pt;
  resting label "default" when `selection == nil`; placeholder frame reduced to 160 pt.
- `Sources/AppShell/AppShell.swift` — cluster-strip toggle `ToolbarItem` removed; inspector
  toggle `ToolbarItem` moved to last declaration in the toolbar block; `NavigationSplitView`
  `.onChange(of: columnVisibility)` callback added to sync cluster-strip visibility.
- `Sources/AppShell/Shortcuts/KeyboardShortcuts.swift` — View menu entry added:
  "Show Cluster Strip" with shortcut `⌘⇧K`; `K8sManagerCommands` extension updated.
- `Sources/AppShell/Views/Resources/ExportMenu.swift` — toolbar injection removed from
  `ExportMenuContainer` modifier; view retained as `RowActionMenu` submenu content.
- `Sources/AppShell/Views/Resources/RowActionMenu.swift` — "Export…" submenu added with
  CSV / YAML / JSON actions wired to existing export service.
- 15× list view files — `.modifier(ExportMenuContainer(...))` call removed from each:
  `PodsListView.swift`, `DeploymentsListView.swift`, `StatefulSetsListView.swift`,
  `DaemonSetsListView.swift`, `ReplicaSetsListView.swift`, `ServicesListView.swift`,
  `IngressesListView.swift`, `ConfigMapsListView.swift`, `SecretsListView.swift`,
  `PersistentVolumeClaimsListView.swift`, `HPAListView.swift`, `LeasesListView.swift`,
  `LimitRangesListView.swift`, `PodDisruptionBudgetsListView.swift`,
  `ResourceQuotasListView.swift`.

## More information

- ADR-0021 — App shell design system; design-system invariant for icon-only chrome buttons.
- ADR-0051 — Multi-cluster workspace; top-right chrome contract extended by this ADR.
- ADR-0069 — Global namespace pill; pill width and label defaults amended by this ADR.
- ADR-0072 — Apple-native window chrome consolidation; cluster-strip toggle amended by this ADR.
- ADR-0073 — Inspector trailing column; inspector toggle placement amended by this ADR.
- ADR-0023 — UX patterns; keyboard shortcut registry; `⌘\` (assistant) and `⌘⇧K` (strip) are
  registered shortcut slots.
- ADR-0050 — Resource navigation taxonomy; `RowActionMenu` extended by this ADR.
- WWDC23 — "Inspectors in SwiftUI" — canonical reference for far-trailing inspector toggle
  placement.

## Amendments

*(This section will be appended by future ADRs that refine this decision.)*
