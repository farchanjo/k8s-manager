# ADR-0069 — Global namespace pill in top-right chrome toolbar

- Status — Accepted (ratified 2026-05-16)
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none)
- Informed — (none)
- Supersedes — ADR-0053 (global namespace filter and resource selection propagation)
- Refines — ADR-0021 (app shell design system and main layout), ADR-0051 (multi-cluster workspace)
- Tags — ui, namespace-filter, app-shell, chrome, pill, toolbar

## Context and problem statement

ADR-0053 introduced `GlobalNamespacePicker` — a folder-icon plus SwiftUI `Picker` menu dropdown
rendered in `SidebarCanvasView.headerBar` above the tab bar. The implementation shipped in the
Onda 3 wave.

An operator UX review of a running build revealed two concerns:

1. **Visual prominence**: the canvas-header strip sits between the cluster strip and the tab bar,
   a region that has low ambient contrast and draws the eye only during tab navigation. A single
   dropdown there competes visually with back/forward navigation arrows and has no persistent
   affordance in the operator's peripheral attention.

2. **Style mismatch**: Config-category views (ConfigMaps, Secrets, HPA, Leases, LimitRanges,
   PodDisruptionBudgets, ResourceQuotas) were added in Onda 2 after ADR-0053 was ratified. They
   each shipped their own per-view `TextField("Namespace", …)` pill in the macOS window toolbar.
   Operators saw both surfaces simultaneously — a `Picker` dropdown in the header strip AND a
   `TextField` pill in the toolbar — causing confusion about which control was canonical.

The operator review concluded that the pill style (compact, always-visible, in the unified window
toolbar row) is preferable to the form-style Picker dropdown. The top-right chrome already hosts
assistant, notifications, and user-menu controls. Placing the namespace pill immediately to the
left of those controls gives it a consistent anchor point without adding a dedicated header strip.

## Decision drivers

The drivers from ADR-0053 are preserved and extended:

- **Single source of truth for filter state** — one control, one actor, one namespace for the
  active cluster.
- **Filter persistence across tab switches** — selecting a namespace in Pods persists when
  switching to Deployments.
- **Per-cluster scope** — `NamespaceFilterActor` is keyed by `ClusterId`; switching clusters
  never bleeds filter state.
- **No domain-core leakage** — presentation concern only; `AppShell` package boundary enforced
  per ADR-0020.
- **Observation compatibility** — Swift 6 `@Observable @MainActor` view models, `@Dependency`
  (swift-dependencies), `AsyncStream`; unchanged from ADR-0053.
- **Visual hierarchy** — the pill is a secondary affordance; placing it in the chrome row
  (alongside assistant/notifications) matches the hierarchy Lens and k9s use: cluster strip
  at left, namespace filter near top-right, tab bar below.
- **Fewer clicks** — the pill label shows the active namespace at a glance. Tapping opens a
  menu. A refresh button forces an immediate namespace re-fetch. No header strip expansion
  required.
- **Uniform per-view picker removal** — all per-view `TextField("Namespace", …)` instances are
  removed; only the chrome pill remains.

## Considered options

- **Option A** — Pill (`GlobalNamespacePill`) in the top-right chrome, left of
  `AssistantToggleButton`. Canvas-header `GlobalNamespacePicker` removed. (chosen)
- **Option B** — Keep ADR-0053 dropdown in canvas header; remove per-view TextFields;
  accept the lower visibility.
- **Option C** — Embed namespace segments as a separate segment control inside the tab bar row
  (similar to the Lens cluster/namespace breadcrumb at the top of the resource panel).

## Decision outcome

Chosen option — **Option A**, because:

- The top-right chrome row is the already-established anchor for persistent, cluster-scoped
  controls (assistant, notifications, user menu); adding the namespace pill there is
  compositionally consistent.
- The pill style (`HStack` with rounded background + trailing chevron menu) is visually lighter
  than a `Picker` menu and more compact than a full-width `TextField`.
- Placing the pill in the chrome removes the need for a separate header strip above the tab bar,
  eliminating the vertical layout jitter that appeared when `activeClusterId` changed.
- Option B retains the lower-visibility location operators found unintuitive.
- Option C embeds namespace state in the tab bar, coupling two orthogonal concerns (tab
  navigation and resource filtering) and complicating the `TabBarView` layout.

### NamespaceFilterActor

**Unchanged from ADR-0053.** The actor definition, `DependencyKey`, and the `current(for:)` /
`setNamespace(_:for:)` / `stateStream(for:)` API surface remain exactly as specified. The
composition-root wiring in `K8sManagerApp.wireSync` is also unchanged — `values.namespaceFilter`
is already registered there and requires no modification.

### GlobalNamespacePill

`GlobalNamespacePill` is a new `public struct` view defined in
`Sources/AppShell/Views/Chrome/GlobalNamespacePill.swift`. It replaces `GlobalNamespacePicker`
(which is deleted).

The pill is rendered in `TopRightChrome` immediately to the left of `AssistantToggleButton`
when `activeClusterId != nil`. `TopRightChrome` accepts a new `activeClusterId: ClusterId?`
parameter injected by its call site in `K8sManagerRootScene` (or the equivalent view that
hosts the chrome bar).

The pill:

1. Resolves `@Dependency(\.namespaceFilter)` and `@Dependency(\.kubernetesResourceList)`.
2. On `.task(id: clusterId)`, seeds the label from `filter.current(for: clusterId)` and
   triggers `loadNamespaces(clusterId:)` to populate the menu.
3. Subscribes to `filter.stateStream(for: clusterId)` via a `for await` loop so external
   mutations (command palette, drawer "filter by namespace" links) keep the pill label in sync.
4. Drives `filter.setNamespace(_:for:)` on menu item selection.
5. Exposes a refresh `Button` (trailing `arrow.clockwise` icon) that re-calls
   `loadNamespaces(clusterId:)` on demand.

Pill shape: `HStack(spacing: 6)` with a `Capsule`-clipped background (`.regularMaterial`).
Width: 180–220 pt. Height: matches the chrome row (32 pt). Label: active namespace name, or
"All namespaces" when `selection == nil`.

When `activeClusterId == nil` (Welcome tab or no cluster pinned), the pill is absent from the
chrome; a `Color.clear.frame(width: 200, height: 32)` placeholder preserves layout stability.

### List view model subscription pattern

**Unchanged from ADR-0053.** The `for await snapshot in namespaceFilter.stateStream(for:)`
loop pattern is the canonical subscription idiom and remains exactly as documented.

The pattern is now **extended to all namespace-scoped Config view models**:

- `ConfigMapsListViewModel`
- `SecretsListViewModel`
- `HPAListViewModel`
- `LeasesListViewModel`
- `LimitRangesListViewModel`
- `PodDisruptionBudgetsListViewModel`
- `ResourceQuotasListViewModel`

Cluster-scoped Config resources (`RuntimeClass`, `PriorityClass`,
`MutatingWebhookConfiguration`, `ValidatingWebhookConfiguration`) have no namespace dimension
and are explicitly excluded from the subscription pattern.

Each namespace-scoped Config view model gains:

```swift
@ObservationIgnored
@Dependency(\.namespaceFilter) private var namespaceFilter

public func start(clusterId: ClusterId, namespace: String?) async {
    self.namespace = await namespaceFilter.current(for: clusterId) ?? namespace
    await fetchRows(clusterId: clusterId)
    for await snapshot in namespaceFilter.stateStream(for: clusterId) {
        if snapshot.namespace == self.namespace { continue }
        self.namespace = snapshot.namespace
        await fetchRows(clusterId: clusterId)
    }
}
```

### Per-view picker removal

Every per-view `TextField("Namespace", text: …)` is removed from the following view files:

- `Sources/AppShell/Views/Resources/Config/ConfigMapsListView.swift` (line 117)
- `Sources/AppShell/Views/Resources/Config/SecretsListView.swift` (line 120)
- `Sources/AppShell/Views/Resources/Config/HPAListView.swift` (line 74)
- `Sources/AppShell/Views/Resources/Config/LeasesListView.swift` (line 70)
- `Sources/AppShell/Views/Resources/Config/LimitRangesListView.swift` (line 72)
- `Sources/AppShell/Views/Resources/Config/PodDisruptionBudgetsListView.swift` (line 70)
- `Sources/AppShell/Views/Resources/Config/ResourceQuotasListView.swift` (line 71)

Each view's `@ToolbarContentBuilder toolbarContent` retains only the Refresh button.
The `Binding` that bridged view ↔ view model namespace state is removed because the view model
now drives namespace internally through the actor subscription.

### Diagram — namespace pill data flow

```text
+---------------------------------------------+
|  K8sManagerRootScene                        |
|  activeClusterId: ClusterId?                |
+--------------------+------------------------+
                     |
                     v
+--------------------+------------------------+
|  TopRightChrome(activeClusterId:)           |
|  +-----------------------------------------+
|  |  GlobalNamespacePill(clusterId:)         |
|  |  - @Dependency(\.namespaceFilter)        |
|  |  - @Dependency(\.kubernetesResourceList) |
|  |  - pill label: selection ?? "All…"      |
|  |  - trailing menu: [ns1, ns2, …, All]    |
|  |  - refresh button: loadNamespaces()     |
|  +-----------------------------------------+
|  AssistantToggleButton  NotificationsButton |
+---------------------------------------------+
                     |
     setNamespace(_:for:) on selection
                     |
                     v
+---------------------------------------------+
|  NamespaceFilterActor (process-wide)        |
|  selected[clusterId] = namespace            |
|  → yields NamespaceFilterSnapshot          |
+---------------------------------------------+
                     |
       stateStream(for: clusterId)
                     |
    +----------------+----------------+
    |                |                |
    v                v                v
 PodsListVM   ConfigMapsListVM  HPAListVM  …
 self.namespace = snapshot.namespace
 await reload(...)
```

### Consequences

Positive:

- Single persistent pill in the chrome row is always visible when a cluster is active,
  regardless of which tab or view is focused.
- Removing the canvas-header strip removes the vertical layout jitter that appeared when
  `activeClusterId` toggled between `nil` and non-nil.
- All Config list views now respond to the global namespace pill; operators no longer need
  to manually type a namespace per view.
- `GlobalNamespacePicker.swift` and the duplicated `TextField` picker logic in Config views
  are deleted, reducing total lines of code.

Negative:

- `TopRightChrome` gains an `activeClusterId` parameter, making the `init` non-trivial.
  Callers must pass the active cluster id down, which requires one additional binding at
  `K8sManagerRootScene`.
- `NamespaceFilterPicker` (in `StatusBadge.swift`) was used exclusively by
  `GlobalNamespacePicker`. Once the old picker is deleted, `NamespaceFilterPicker` becomes
  dead code. It is deleted alongside the picker. `HelmReleasesListView` uses it directly
  and will need its own inline picker until HelmReleases wiring is updated in a follow-up
  round.

## Pros and cons of the options

### Option A — Pill in top-right chrome (chosen)

- Good, because always-visible placement matches the Lens reference UX for namespace context.
- Good, because removal of the header strip simplifies `SidebarCanvasView.headerBar` to just
  navigation arrows.
- Good, because pill style is consistent with the existing chrome controls' visual language.
- Bad, because `TopRightChrome` init now carries `activeClusterId`.

### Option B — Keep ADR-0053 canvas-header dropdown

- Good, because no changes to `TopRightChrome` or its callers.
- Bad, because the location was rated unintuitive by the operator UX review.
- Bad, because per-view Config TextFields still need to be removed regardless.

### Option C — Namespace as tab-bar segment

- Good, because the tab bar is the most prominent chrome element.
- Bad, because it conflates tab navigation state with resource filter state — two orthogonal
  concerns sharing one visual component.
- Bad, because it complicates the uniform `TabChip` design from ADR-0050.

## Confirmation

- `Sources/AppShell/Views/Chrome/GlobalNamespacePill.swift` — new view; the only namespace
  filter chrome component.
- `Sources/AppShell/Views/Chrome/TopRightChrome.swift` — accepts `activeClusterId: ClusterId?`;
  renders `GlobalNamespacePill` when non-nil.
- `Sources/AppShell/Views/Sidebar/SidebarCanvasView.swift` — `headerBar` no longer renders
  `GlobalNamespacePicker`; the canvas header strip retains only navigation arrows.
- `Sources/AppShell/Views/GlobalNamespacePicker.swift` — deleted.
- Seven Config view models gain `@Dependency(\.namespaceFilter)` and the `for await` loop.
- Seven Config list views drop their `TextField("Namespace", …)` toolbar items.
- `Tests/AppShellTests/GlobalNamespacePillTests.swift` — unit tests covering: initial state
  (no selection), selection round-trip, namespace list load path, actor stream integration.

## More information

- ADR-0011 — Swift concurrency conventions; `NamespaceFilterActor` follows actor isolation rules.
- ADR-0020 — SwiftPM workspace topology; `GlobalNamespacePill` lives in `AppShell` only.
- ADR-0034 — State-driven realtime UI; the `AsyncStream` projection idiom is reused verbatim.
- ADR-0037 — Concurrency lifecycle invariants; `for await` subscription respects the documented
  cancellation contract.
- ADR-0050 — Resource navigation taxonomy; list views referenced here are opened from
  `DocumentTab.resourceList` cases.
- ADR-0051 — Multi-cluster workspace; the chrome row extended here is documented in
  §"Top-right chrome" as the canonical location for persistent cluster-scoped controls.
- ADR-0053 — Superseded. Decision rationale preserved for historical reference.

## Amendments

### ADR-0074 — 2026-05-16 — Pill width narrowed; resting label changed to "default"

ADR-0074 (Apple HIG toolbar header consolidation) amends §"Pill shape" of this ADR. The pill
frame width is narrowed from 180–220 pt to 140–180 pt. The resting label when `selection == nil`
changes from "All namespaces" to "default"; "All namespaces" is retained as a menu item label
only. The `Color.clear` layout placeholder is reduced from 200 pt to 160 pt to match the narrowed
frame. All other pill behaviour — actor wiring, subscription idiom, refresh button, and menu
construction — is unchanged.

Forward reference: ADR-0074.
