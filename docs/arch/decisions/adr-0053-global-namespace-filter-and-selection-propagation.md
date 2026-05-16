# ADR-0053 — Global namespace filter and resource selection propagation

- Status — Superseded by ADR-0069
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0050 (resource navigation taxonomy), ADR-0051 (multi-cluster workspace),
  ADR-0021 (app shell design system and main layout), ADR-0034 (state-driven realtime UI
  architecture)
- Tags — ui, namespace-filter, app-shell, observation, sidebar, selection, drawer

## Supersession

This ADR is superseded by
[ADR-0069](adr-0069-global-namespace-pill-toolbar.md) (ratified 2026-05-16).

ADR-0069 replaces `GlobalNamespacePicker` (canvas-header folder-icon dropdown) with
`GlobalNamespacePill` (pill in the top-right chrome row, left of `AssistantToggleButton`).
The `NamespaceFilterActor`, its `DependencyKey`, and the `for await stateStream` subscription
pattern documented below are **unchanged** by ADR-0069 and remain canonical. The per-view
`TextField("Namespace", …)` instances in Config views, which the original ADR did not address
(they were added after ratification), are removed by ADR-0069.

The remainder of this document is kept verbatim for historical reference.

## Context and problem statement

ADR-0050 defined the multi-document tab system and the categorical sidebar tree. ADR-0051 defined
the cluster strip, per-cluster sidebar tree, and the detail drawer (right slide-in inspector). Neither
ADR specified two emergent concerns that surfaced during the Onda 3 implementation:

1. **Namespace filter scope** — every workload list view (`PodsListView`, `DeploymentsListView`,
   `StatefulSetsListView`, etc.) initially owned its own `NamespaceFilterPicker` in a SwiftUI
   `ToolbarItem`. Switching tabs lost the selection. Two views of the same kind in different tabs
   could disagree on the active filter. The list-view-local picker also could not be reused for
   non-list surfaces (events, custom resources, Helm releases).

2. **Row selection → drawer propagation** — `ActiveTabContentView` owns the detail drawer
   (`ResourceDetailDrawer`) via `.inspector`. The drawer needs a `ResourceRef` whenever the operator
   selects a row in a list view. Each list view has a private `selectedId: String?` bound to its
   `Table`. There was no documented pattern to lift that selection up to the drawer host.

Both concerns are cross-cutting: they affect every list view added in Onda 2/3 and every list view
that lands in future onda waves. Without a single canonical pattern, each new view would invent its
own (incompatible) approach.

## Decision drivers

- **Single source of truth for filter state** — the operator's mental model is *"I'm working in
  namespace X right now."* That state belongs to the workspace, not to a tab.
- **Filter persistence across tab switches** — choosing a namespace in Pods then opening a
  Deployments tab MUST inherit the selection without re-picking.
- **Per-cluster scope** — operators with multiple pinned clusters select different namespaces per
  cluster (e.g. `prod` on the EKS cluster, `default` on a local kind cluster). The filter MUST be
  scoped to `ClusterId`, never global to the process.
- **Lift selection without prop-drilling** — list views are added incrementally; each new view
  cannot require passing a closure through the entire `ActiveTabContentView → workloadListView →
  <Kind>ListView` chain. SwiftUI `Environment` is the idiomatic SwiftUI lift.
- **No domain-core leakage** — both the picker and the selection propagation are presentation
  concerns. They MUST NOT touch domain cores or adapter packages, preserving the ADR-0020
  composition-root invariant.
- **Observation compatibility** — Swift 6 `@Observable @MainActor` view models read shared state via
  `@Dependency` (pointfreeco/swift-dependencies) and `AsyncStream`; the new patterns MUST follow the
  existing ADR-0034 idioms.

## Considered options

- **Option A** — `NamespaceFilterActor` (cluster-scoped) + `GlobalNamespacePicker` in canvas header
  + `\.onResourceSelect` SwiftUI `Environment` closure (chosen).
- **Option B** — `@AppStorage("namespace_filter_<clusterId>")` per cluster + `PreferenceKey` lift
  for selection.
- **Option C** — keep per-list-view pickers; share a shared `@Observable` view model passed via
  `@EnvironmentObject` (legacy `ObservableObject`).

## Decision outcome

Chosen option — **Option A**, because:

- A dedicated actor mirrors the existing `ClusterStripActor` / `OpenTabsActor` ownership pattern
  (ADR-0050, ADR-0051) and keeps Swift concurrency invariants explicit (ADR-0011, ADR-0037).
- `AsyncStream` projection lets every observer (the picker and every workload list view model)
  receive filtered snapshots without coupling between them.
- A SwiftUI `Environment` closure for selection avoids prop-drilling without leaking observable
  references to leaf views.
- Option B (`@AppStorage`) implies eager disk persistence; the filter is transient session state and
  should NOT survive crashes or app restarts the way pinned clusters do.
- Option C (`@EnvironmentObject`) regresses the codebase to pre-Observation ergonomics and creates
  a parallel state surface incompatible with the existing `@Observable` adoption.

### NamespaceFilterActor

A single `NamespaceFilterActor` is registered at the composition root (`K8sManagerApp`) via
`prepareDependencies { $0.namespaceFilter = ... }`. Every workload list view model resolves it via
`@Dependency(\.namespaceFilter)` (pointfreeco/swift-dependencies). The actor owns:

- `selected: [ClusterId: String]` — per-cluster current namespace. Missing key = "all namespaces".
- Per-subscriber continuations keyed by `(UUID, ClusterId)` so a change in cluster A does not wake
  subscribers watching cluster B.

Public API:

- `current(for: ClusterId) async -> String?` — read the current namespace.
- `setNamespace(_:for:) async` — mutate; no-op when unchanged.
- `nonisolated stateStream(for: ClusterId) -> AsyncStream<NamespaceFilterSnapshot>` — receive a
  snapshot for the requested cluster only.

`NamespaceFilterSnapshot` is `Sendable` and carries `(clusterId, namespace?)`. The stream yields the
current value immediately, then yields on every mutation, then completes when the subscriber's
`Task` is cancelled.

Persistence is intentionally **transient**: the filter is session state. Surviving an app restart
should NOT carry over a stale filter that could mask deployments in unfamiliar namespaces. Pinned
clusters survive restarts (ADR-0051); the active filter does not.

### GlobalNamespacePicker

A single `GlobalNamespacePicker` lives in the canvas header (`SidebarCanvasView`) above the tab bar.
It is rendered only when `AppShellView` has resolved an `activeClusterId` from `ClusterStripActor`.
The picker:

1. Resolves `@Dependency(\.namespaceFilter)` and `@Dependency(\.kubernetesResourceList)`.
2. On `.task(id: clusterId)`, seeds the dropdown from `filter.current(for: clusterId)` and fetches
   the cluster's namespace list (`GroupVersionKind.core("Namespace")`).
3. Subscribes to `filter.stateStream(for: clusterId)` so external mutations (future command palette,
   "filter by namespace" links from drawers) keep the dropdown in sync.
4. Drives `filter.setNamespace(_:for:)` on user selection.

The picker uses the shared `NamespaceFilterPicker` chip (still defined in `Workloads/StatusBadge.swift`)
which accepts a `namespaces: [String]` list. When the API call fails the chip falls back to a fixed
quick-pick set so the picker never becomes unusable.

The per-list-view `ToolbarItem` instances of `NamespaceFilterPicker` are **removed** from every
workload list view. The dropdown is exactly one and exactly here.

### List view model subscription pattern

Every workload list view model that filters by namespace (`PodsListViewModel`,
`DeploymentsListViewModel`, `StatefulSetsListViewModel`, `DaemonSetsListViewModel`,
`ReplicaSetsListViewModel`, `ReplicationControllersListViewModel`, `JobsListViewModel`,
`CronJobsListViewModel`) implements `start(clusterId:namespace:)` as:

```swift
@ObservationIgnored
@Dependency(\.namespaceFilter) private var namespaceFilter

public func start(clusterId: ClusterId, namespace: String?) async {
    self.namespace = await namespaceFilter.current(for: clusterId) ?? namespace
    await reload(clusterId: clusterId)
    for await snapshot in namespaceFilter.stateStream(for: clusterId) {
        if snapshot.namespace == self.namespace { continue }
        self.namespace = snapshot.namespace
        await reload(clusterId: clusterId)
    }
}
```

The `for await` loop owns the lifetime of the subscription. SwiftUI cancels it automatically when
the view disappears because the call site uses `.task(id: clusterId)`.

The `namespace` init parameter remains for backward compatibility with the `DocumentTab.resourceList`
case (which still carries an optional namespace per ADR-0050). When the parameter is `nil` and the
actor has no entry for the cluster, the list starts in "all namespaces" mode — the existing default.

### Resource selection propagation (`\.onResourceSelect`)

A SwiftUI `Environment` key is added at `app_shell/Ports/SelectedResourceRefKey.swift`:

```swift
private struct OnResourceSelectKey: EnvironmentKey {
    static let defaultValue: @Sendable @MainActor (ResourceRef?) -> Void = { _ in }
}

public extension EnvironmentValues {
    var onResourceSelect: @Sendable @MainActor (ResourceRef?) -> Void { ... }
}
```

`ActiveTabContentView` injects a closure that stores the selection in its `@State private var
selectedRef: ResourceRef?`. The closure is reachable from every descendant view through the standard
`@Environment(\.onResourceSelect)` accessor.

List views call `onResourceSelect(ResourceRef?)` from `.onChange(of: viewModel.selectedId)`:

- `nil` clears the drawer.
- A non-nil `ResourceRef` opens (or updates) `ResourceDetailDrawer` via the existing
  `.inspector(isPresented:)` modifier.

This Environment closure is **read-only signalling** — it does not mutate domain state. The drawer
lifecycle remains owned by `ActiveTabContentView`.

### Diagram — selection flow

```text
+--------------------+            (closure)             +--------------------------+
| DeploymentsList    | --- onResourceSelect(ref) ---> | ActiveTabContentView      |
| .onChange(selId)   |                                 |  selectedRef = ref        |
+--------------------+                                 |  .inspector(...)          |
                                                       +-----------+--------------+
                                                                   |
                                                                   v
                                                       +-----------+--------------+
                                                       | ResourceDetailDrawer     |
                                                       | (drawer presented)       |
                                                       +--------------------------+
```

### Composition root wiring

`K8sManagerApp.swift` registers the new actor alongside the existing strip and tabs actors:

```swift
prepareDependencies { values in
    values.clusterStrip = clusterStripActor
    values.openTabs = openTabsActor
    values.namespaceFilter = NamespaceFilterActor()
    // ...
}
```

The actor has no persistence and no `loadFromDisk()`, so it does not appear in `wireAsync()`.

### Consequences

Positive:

- Single dropdown in the canvas header filters every workload list view simultaneously, matching
  the Lens / k9s / OpenLens UX baseline.
- Tab switching never loses filter context: the namespace selection is workspace state, not tab
  state.
- Per-cluster scoping means switching the active cluster never reveals stale filters from another
  cluster.
- The `\.onResourceSelect` closure is a one-line opt-in for new list views; no prop-drilling.
- The detail drawer (`ResourceDetailDrawer`) wiring from ADR-0051 finally activates without each
  list view needing to embed drawer state.

Negative:

- `NamespaceFilterActor` is a new global actor; subscriber bookkeeping must be carefully managed to
  avoid Task leaks. Mitigation: each `stateStream` uses `continuation.onTermination` to unregister.
- The picker location in the canvas header **extends** ADR-0051's chrome layout (which scoped
  top-right chrome to assistant / notifications / preferences). The header strip is documented in
  this ADR's "GlobalNamespacePicker" section but the ADR-0051 §"Top-right chrome" wording is not
  contradicted: the namespace picker lives above the tab bar, not in the unified window toolbar.
- The Environment closure introduces an implicit dependency between list views and
  `ActiveTabContentView`; views that render outside that view's subtree will silently no-op the
  selection. This is acceptable because every list view today is reached through the tab system.

## Pros and cons of the options

### Option A — Actor + global picker + Environment closure (chosen)

- Good, because the actor mirrors existing ADR-0050 / ADR-0051 ownership patterns.
- Good, because `AsyncStream` matches the ADR-0034 reactive-stack idiom every other actor uses.
- Good, because the Environment closure scales to every future list view without prop-drilling.
- Bad, because it adds a new actor to maintain (registration, subscriber bookkeeping).

### Option B — `@AppStorage` per cluster + `PreferenceKey` lift

- Good, because `@AppStorage` provides automatic persistence.
- Bad, because the filter is transient session state; persisting it across launches risks operator
  confusion when work resumes in an unfamiliar namespace.
- Bad, because `PreferenceKey` is one-shot and one-way — drawer state cannot be cleared with the
  same idiom.

### Option C — `@EnvironmentObject` shared `ObservableObject`

- Good, because it requires no new actor.
- Bad, because it regresses to pre-Observation ergonomics, conflicting with the `@Observable`
  adoption in every existing view model.
- Bad, because `@EnvironmentObject` shares mutable state across SwiftUI without an actor boundary,
  making concurrency reasoning harder (ADR-0011, ADR-0037).

## Confirmation

- `Sources/AppShell/Actors/NamespaceFilterActor.swift` defines the actor and `DependencyKey`. The
  `liveValue` and `testValue` are fresh `NamespaceFilterActor()` instances; production wires the
  singleton via `prepareDependencies` at the composition root.
- `Sources/AppShell/Ports/SelectedResourceRefKey.swift` defines the `\.onResourceSelect`
  `EnvironmentKey`. The default value is `{ _ in }` so views outside `ActiveTabContentView` silently
  no-op the call.
- `Sources/AppShell/Views/GlobalNamespacePicker.swift` defines the single picker; the only call
  site is `Sources/AppShell/Views/Sidebar/SidebarCanvasView.swift` rendered above the tab bar.
- All 8 workload list view models follow the subscription pattern (see "List view model
  subscription pattern" above). The pattern is the only canonical way to filter a workload list
  view by namespace; new list views MUST adopt it.
- Unit tests in `Tests/AppShellTests/NamespaceFilterActorTests.swift` (planned) cover:
  - Snapshot is yielded immediately on subscription with the current value.
  - Setting a namespace for cluster A wakes only subscribers of cluster A.
  - Repeated `setNamespace` with the same value is a no-op (no broadcast).
- A SwiftUI snapshot test (planned) verifies the picker dropdown lists all namespaces returned by
  the live `KubernetesResourceListPort` adapter for a fixture kubeconfig.

## More information

- ADR-0011 — Swift concurrency conventions; `NamespaceFilterActor` follows the actor isolation
  rules established here.
- ADR-0020 — SwiftPM workspace topology; the new actor and view live in `AppShell` only, never
  cross adapter boundaries.
- ADR-0034 — State-driven realtime UI; the `AsyncStream` projection idiom is reused verbatim.
- ADR-0037 — Concurrency lifecycle invariants; the `for await` subscription loop respects the
  documented cancellation contract.
- ADR-0050 — Resource navigation taxonomy; the workload list views referenced here are the same
  views opened from `DocumentTab.resourceList` cases.
- ADR-0051 — Multi-cluster workspace; the canvas header strip introduced here sits between the
  cluster strip (left) and the tab bar (below) — extending the chrome layout without contradicting
  ADR-0051 §"Top-right chrome".
