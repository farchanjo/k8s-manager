# ADR-0073 — Inspector trailing column substitutes resource detail tabs

- Status — Accepted (ratified 2026-05-16)
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none)
- Informed — (none)
- Refines — ADR-0021 (app shell design system and main layout),
  ADR-0034 (state-driven realtime UI architecture),
  ADR-0050 (resource navigation taxonomy + tab system),
  ADR-0070 (sidebar selection and active tab bidirectional sync)
- Amends — ADR-0050 (resource navigation taxonomy + tab system),
  ADR-0070 (sidebar selection and active tab bidirectional sync)
- Tags — ui, inspector, navigation-split-view, app-shell, resource-detail, tabs

## Context and problem statement

ADR-0050 defines the multi-document tab system: every row-click in a resource list dispatches
`openTabs.openTab(.resourceDetail(...))`, opening a dedicated `DocumentTab` that renders the full
detail view for the selected resource. After ten to fifteen minutes of typical operator use, the tab
bar accumulates fifteen or more tabs — one per Pod inspected, one per Deployment reviewed, one per
Service checked. The operator must then close tabs manually to keep the bar navigable.

This pattern is inconsistent with the Apple HIG canonical model for "details of a selected item".
Apple's own applications — Notes (note inspector), Pages (layout inspector), Xcode (Attributes
inspector), Numbers (format inspector), and Finder (Get Info panel) — all use a persistent trailing
column or panel that updates its content to reflect the currently selected item. A new panel is
never opened for each selection. WWDC23 session "Inspectors in SwiftUI" formalised this pattern
with the `.inspector(isPresented:)` modifier available on macOS 14+.

The tab-per-detail model was appropriate when K8sManager had no Inspector surface. Now that macOS 14
ships `.inspector(isPresented:)` and the project targets macOS 14+ exclusively (ADR-0001,
README.md §Product summary), the Inspector primitive is the correct container for resource detail
viewing. Tabs are the correct container for workspace-scoped views and bulk operational surfaces
where the operator deliberately leaves the resource list context.

## Decision drivers

- **Tab bar hygiene** — the tab bar must remain navigable across a full operator session. Fifteen
  spontaneously opened detail tabs degrade navigability within minutes.
- **Apple HIG canonical pattern** — `.inspector(isPresented:)` is the macOS 14+ primitive for
  trailing inspector columns. It is used by every major Apple productivity application.
- **ADR-0034 state derivation** — Inspector content is a derived view of the currently selected row,
  not independent state. Deriving it from actor state rather than opening a new tab is consistent
  with the `AsyncStream`-based projection idiom from ADR-0034.
- **ADR-0050 tab system scope** — tabs are designed for workspace-scoped surfaces (Welcome tab,
  ClusterOverview, Helm releases) and bulk operational surfaces (exec, logs, port-forward, YAML
  editor, drift inspector). They are not designed for ephemeral per-row detail viewing.
- **Swift 6 concurrency** — `ResourceInspectorViewModel` must be `@Observable @MainActor`-isolated,
  following the view model pattern from ADR-0034. Inspector state changes must be driven by actor
  subscriptions, not imperative bindings.

## Considered options

- **Option A** — Inspector trailing column via `NavigationSplitView` third column +
  `.inspector(isPresented:)` (chosen).
- **Option B** — Detail popover on row hover: a `popover(isPresented:)` that appears on the hovered
  row and shows a condensed detail card.
- **Option C** — Keep the status quo: `DocumentTab` per row-click, tab bar accumulates detail tabs.

## Decision outcome

Chosen option — **Option A**, because:

- `.inspector(isPresented:)` is the macOS 14+ canonical primitive; using it requires no custom
  layout work and produces the system-standard trailing column affordance.
- The Inspector is a persistent, session-scoped surface. It does not open new tabs; it updates its
  content reactively as `selectedRow` changes. This matches the ADR-0034 state-derivation idiom
  exactly.
- Option B (hover popover) is too transient: it dismisses on mouse-out, cannot scroll to long YAML
  manifests, and does not provide the persistent side-by-side viewing that Xcode and Finder
  demonstrate.
- Option C was explicitly rejected by the operator on 2026-05-16 as the source of tab bar
  fragmentation.

### Invariant

> **When a resource list has a selected row AND the Inspector is visible, the Inspector reflects
> that row's spec, status, and events. When the selection clears (row deselected or list
> navigated away), the Inspector shows an empty state until a new row is selected.**

Corollary: only one `ResourceInspectorViewModel` is active per window at any time. It is keyed by
`(clusterId, resourceKind, resourceName, namespace?)`. When the operator selects a different row,
the view model updates the key and re-fetches. The previous row's detail data is evicted.

### Inspector visibility

- Default state: closed.
- Toggle: keyboard shortcut `⌘⌥0` (matches Xcode Attributes inspector toggle).
- Toolbar button: a `ToolbarItem(placement: .inspector)` renders the standard inspector toggle icon
  (`sidebar.trailing`) following the WWDC23 inspector demo pattern.
- Persistence: `WindowLayout.mainWindow.inspectorVisible` (field already defined in the existing
  `window_layout.cue` schema; no schema migration required for this field).

### NavigationSplitView extension to three columns

The `NavigationSplitView` currently renders two columns: sidebar and content. The Inspector
replaces the prior ADR-0051 "detail drawer" (a slide-in right panel). The Navigator split is
extended as follows:

```swift
NavigationSplitView {
    SidebarView()                // Column 1: sidebar tree + cluster navigation
} content: {
    ContentView()                // Column 2: tab bar + resource list + overlays
} detail: {
    ResourceInspectorView()      // Column 3 — managed by .inspector modifier
}
.inspector(isPresented: $inspectorVisible) {
    ResourceInspectorView(viewModel: inspectorViewModel)
}
```

On macOS 14+, `.inspector(isPresented:)` drives the trailing column into and out of view with the
system-standard slide animation. The `NavigationSplitView` three-column layout contract from
ADR-0021 is restored: sidebar | content | inspector.

### ResourceInspectorViewModel

`ResourceInspectorViewModel` is a new `@Observable @MainActor`-isolated class defined in
`Sources/AppShell/ViewModels/ResourceInspectorViewModel.swift`.

Responsibilities:

- Maintains `selectedKey: InspectorKey?` where `InspectorKey` is the tuple
  `(clusterId: ClusterId, kind: ResourceKind, name: String, namespace: String?)`.
- On `selectedKey` change: cancels any in-flight subscription, creates a new `for await` loop
  over the watch stream for the new key via `KubernetesApiPort` (ADR-0002), and publishes
  `inspectorContent: ResourceInspectorContent?`.
- Exposes `isLoading: Bool` to drive the skeleton loader (ADR-0071) during initial fetch.
- When `selectedKey == nil` or the Inspector is closed (`inspectorVisible == false`): publishes
  `inspectorContent = nil` and shows the empty state.
- Follows the ADR-0034 `AsyncStream` subscription idiom:

```swift
func load(key: InspectorKey) async {
    currentLoadTask?.cancel()
    isLoading = true
    currentLoadTask = Task {
        for await resource in watchPort.stream(clusterId: key.clusterId,
                                               kind: key.kind,
                                               name: key.name,
                                               namespace: key.namespace) {
            inspectorContent = ResourceInspectorContent(resource: resource)
            isLoading = false
        }
    }
}
```

### ResourceInspectorContent protocol

Inspector content per resource kind is defined via `ResourceInspectorContent`, a Swift protocol
with associated type `Body: View`. Each supported kind provides a conforming struct:

- `PodInspectorContent` — spec, containers, conditions, events, Prometheus sparklines.
- `DeploymentInspectorContent` — spec, rollout status, pod template, conditions, events.
- `ServiceInspectorContent` — spec, endpoints, selector labels, events.
- Additional kinds follow the same extension pattern; the protocol acts as the Inspector's
  open extension point.

Inspector content views are defined in `Sources/AppShell/Views/Inspector/<Kind>InspectorView.swift`.

### Row tap routing

When an operator taps a row in any resource list view, the routing logic is:

1. If the resource kind has a registered `ResourceInspectorContent` conformance AND the Inspector
   is visible: the tap updates `inspectorViewModel.selectedKey` and shows the Inspector. No tab is
   opened. No call to `openTabs.openTab(_:)` is made.
2. If the resource kind has a registered `ResourceInspectorContent` conformance AND the Inspector
   is not visible: the tap opens the Inspector (sets `inspectorVisible = true`) and updates
   `selectedKey`. No tab is opened.
3. If the resource kind does NOT have a registered `ResourceInspectorContent` conformance (e.g.
   synthetic kinds, `TokenRequest`): the existing ADR-0050 tab-open path applies unchanged.

The "Open in Tab" context menu action remains available on every resource row and bypasses this
routing, opening a `DocumentTab.resourceDetail` for operators who need side-by-side comparison.
This action routes through `openTabs.openTab(_:)`, preserving the ADR-0070 sync invariant.

### Tab kinds that remain as DocumentTabs

The following surfaces continue to open as `DocumentTab` instances, unchanged from ADR-0050:

- `clusterOverview` — workspace-scoped; not a single-resource detail.
- `helmReleases` and `helmDetail` — Helm surfaces; no inspector content defined.
- `events` — cluster-wide event feed; not a single-resource detail.
- `terminalSession` — bulk operational surface (pod exec, node debug).
- `resourceDetail` opened via "Open in Tab" context menu — operator-explicit.
- Log stream (`podLogs`) — bulk operational; requires full content area width.
- Port-forward session — bulk operational.
- YAML editor (dedicated tab) — deep edit session per ADR-0064 §Decision outcome, Option C.
- Drift inspector and Helm release detail — analytical surface requiring full content.

### Detail drawer retirement

The ADR-0051 "detail drawer" (slide-in right panel from the `NavigationSplitView` trailing edge)
is retired by this ADR. Its content inventory — resource header, action toolbar, metrics panel,
properties grid, containers section, volumes section, events section — migrates into the
`ResourceInspectorContent` per-kind protocol implementations. The drawer's keyboard shortcut
`⌘⇧I` is reassigned to the Inspector toggle (consistent with `⌘⌥0` from Xcode; both are
documented in ADR-0023 shortcut registry addendum).

### Consequences

Positive:

- Tab bar accumulation is eliminated for the most common operator action (inspecting a resource
  row). The tab bar retains only intentional workspace tabs.
- The Apple HIG `.inspector(isPresented:)` primitive handles show/hide animation, width
  persistence, and `NSSplitView` layout automatically — no custom split implementation is needed.
- `ResourceInspectorViewModel` follows the ADR-0034 `AsyncStream` projection pattern exactly;
  no new architectural idiom is introduced.
- Inspector visibility is a single boolean persisted in `WindowLayout.mainWindow.inspectorVisible`,
  which already exists in the schema.

Negative:

- Side-by-side comparison of two Pods requires the operator to explicitly use "Open in Tab" from
  the context menu. There is no native two-inspector layout in this ADR; that use case is deferred
  to a future Inspector pop-out ADR.
- `ResourceInspectorContent` conformances must be authored per kind. The initial wave ships
  `PodInspectorContent`, `DeploymentInspectorContent`, and `ServiceInspectorContent`; all other
  kinds fall back to the tab-open path until conformances are added.
- The ADR-0051 detail drawer is retired; its test coverage (Gherkin scenarios for drawer open, action
  toolbar, metrics panel) must be migrated to equivalent Inspector scenarios.

## Pros and cons of the options

### Option A — Inspector trailing column (chosen)

- Good, because `.inspector(isPresented:)` is the macOS 14+ system primitive; no custom layout.
- Good, because Inspector content is a derived view — it follows ADR-0034 exactly.
- Good, because tab bar stays minimal; operators can work for hours without manual tab hygiene.
- Bad, because side-by-side comparison of two resources requires context-menu "Open in Tab".

### Option B — Detail popover on row hover

- Good, because no new column is added to `NavigationSplitView`; layout is simpler.
- Bad, because popovers dismiss on mouse-out; operators cannot scroll long YAML manifests.
- Bad, because hover-reveal is not discoverable by keyboard-only operators (ADR-0023 a11y drivers).

### Option C — Keep tab-per-row (status quo)

- Good, because zero migration; existing tab system is fully tested.
- Bad, because the operator explicitly rejected it as the source of tab bar fragmentation.
- Bad, because it diverges from Apple HIG and the four major Apple application references.

## Confirmation

The following file paths are stubs; exact line numbers are filled by the implementation wave.

- `Sources/AppShell/ViewModels/ResourceInspectorViewModel.swift` — new file; `@Observable
  @MainActor` class; `InspectorKey`, `load(key:)`, `AsyncStream` subscription loop.
- `Sources/AppShell/Views/Inspector/ResourceInspectorView.swift` — new file; SwiftUI view
  dispatching on `inspectorContent` type to the appropriate per-kind view.
- `Sources/AppShell/Views/Inspector/PodInspectorView.swift` — new file; Pod inspector content.
- `Sources/AppShell/Views/Inspector/DeploymentInspectorView.swift` — new file.
- `Sources/AppShell/Views/Inspector/ServiceInspectorView.swift` — new file.
- `Sources/AppShell/Views/AppShellContentView.swift` (stub) — `.inspector(isPresented:)` modifier
  applied to the `NavigationSplitView`; `inspectorVisible` binding wired to `WindowLayout`.
- `Sources/AppShell/Views/Resources/ResourceListView.swift` (stub) — row tap handler updated to
  route through `inspectorViewModel.load(key:)` for inspector-capable kinds.
- `contexts/app_shell/schemas/window_layout.cue` — no schema change required; `inspectorVisible`
  field already exists.
- `Tests/AppShellTests/ResourceInspectorViewModelTests.swift` — unit tests: selected row updates
  `inspectorContent`; cleared selection produces `nil` content; `InspectorKey` change cancels
  prior subscription task.

## More information

- ADR-0021 — App shell design system; `NavigationSplitView` three-column baseline restored.
- ADR-0034 — State-driven realtime UI; `AsyncStream` subscription idiom reused verbatim.
- ADR-0050 — Resource navigation taxonomy + tab system; amended by this ADR.
- ADR-0051 — Multi-cluster workspace; detail drawer retired and replaced by Inspector.
- ADR-0070 — Sidebar selection and tab sync; amended by this ADR (Inspector "Open in Tab" is a
  new mutation source for `openTabs.openTab(_:)`, but the invariant is unchanged).
- ADR-0071 — Skeleton mandate; `ResourceInspectorViewModel.isLoading` drives skeleton in
  `ResourceInspectorView` during initial load.
- ADR-0072 — Apple-native window chrome consolidation; companion ADR covering Changes 1–5.
- WWDC23 — "Inspectors in SwiftUI" — canonical reference for `.inspector(isPresented:)` usage
  on macOS 14+.

## Amendments

### ADR-0074 — 2026-05-16 — Inspector toggle moved to far-trailing edge; icon differentiates state

ADR-0074 (Apple HIG toolbar header consolidation) amends §"Inspector visibility" of this ADR.
The inspector toggle `ToolbarItem` is now declared last in the window toolbar block (after all
`TopRightChrome` items) so that macOS places it at the rightmost edge of the toolbar, matching the
WWDC23 "Inspectors in SwiftUI" canonical pattern. The icon is differentiated: `sidebar.trailing.fill`
when the inspector is open, `sidebar.trailing` when closed. The keyboard shortcut ⌘⌥0 and the
`WindowLayout.mainWindow.inspectorVisible` persistence field are unchanged.

Forward reference: ADR-0074.
