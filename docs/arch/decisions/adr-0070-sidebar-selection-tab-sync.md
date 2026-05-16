# ADR-0070 — Sidebar selection and active tab bidirectional sync

- Status — Accepted (ratified 2026-05-16)
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none)
- Informed — (none)
- Refines — ADR-0034 (state-driven realtime UI architecture),
  ADR-0050 (resource navigation taxonomy + tab system)
- Tags — sidebar, tab-bar, sync, observation, actor, state-machine

## Context and problem statement

ADR-0050 defines the multi-document tab bar (`OpenTabsActor`) and the hierarchical
sidebar tree (`SidebarTreeViewModel`). Each surface independently tracks its own
active item: the tab bar tracks `activeTabId` inside `OpenTabsActor`; the sidebar
tracks `selectedNode` inside `SidebarTreeViewModel`.

Two distinct desync failure modes were observed in the 56-frame regression recording:

1. **Sidebar leads, tab lags** (frame 14) — the user taps a tab chip directly in the
   tab bar. `OpenTabsActor.focusTab(_:)` fires and the tab bar chip highlights
   correctly, but `SidebarTreeViewModel.selectedNode` stays on the previously
   activated sidebar row, showing "Jobs" highlighted while the active tab is
   "CronJob".

2. **Tab leads, sidebar invisible** — the user opens a tab programmatically (e.g. via
   the command palette or a drawer action button). The tab bar switches but the sidebar
   shows no highlighted node because the sidebar only updates `selectedNode` on
   explicit `activate(_:)` calls.

Neither ADR-0034 nor ADR-0050 documented the invariant governing how these two surfaces
synchronise. Without an explicit invariant, every new view that opens tabs risks
reintroducing the desync.

## Decision drivers

- **Single source of truth** — `OpenTabsActor.activeTabId` is the authoritative source
  for which tab is active. The sidebar `selectedNode` is a derived projection of that
  state, not an independent authority.
- **ADR-0034 reactive idiom** — derived state must flow from `AsyncStream` subscriptions,
  not from imperative setter calls scattered across the view layer.
- **No prop-drilling** — `SidebarTreeViewModel` already resolves `OpenTabsPort` via
  `@Dependency(\.openTabs)` without coupling to any specific view.
- **Bidirectionality** — user taps on a sidebar row must still open or focus the
  corresponding tab (forward direction). The inverse mapping (tab activation → sidebar
  highlight) must flow through the actor stream, not a second callback.
- **Swift 6 strict concurrency** — all state mutations on `SidebarTreeViewModel` are
  `@MainActor`-isolated; the subscription loop runs on `MainActor` via the existing
  `start()` task.

## Considered options

- **Option A** — `selectedNode` derived from `OpenTabsPort.stateStream()` subscription
  inside `SidebarTreeViewModel.start()`, with the inverse mapping implemented as
  `SidebarNode.from(documentTab:)`. Tap on sidebar row calls `activate(_:)` which sets
  `selectedNode` eagerly AND dispatches `openTabs.openTab(_:)` — the subsequent
  actor broadcast then re-derives `selectedNode`, producing a no-op second write.
  (chosen)

- **Option B** — Shared `@Observable` `SelectionCoordinator` object injected into both
  the sidebar view model and the tab bar view model. Two observers watch the same
  mutable property.

- **Option C** — Each view posts a `NotificationCenter` message when it changes
  selection; the other view listens and updates independently.

## Decision outcome

Chosen option — **Option A**, because:

- It reuses the existing `OpenTabsPort.stateStream()` surface already consumed by
  `TabBarViewModel`; no new inter-object coupling is introduced.
- `SidebarNode.from(documentTab:)` is a pure function with no async work — the inverse
  mapping is O(1) and deterministic.
- Option B requires a shared mutable reference crossing actor boundaries, violating
  Swift 6 `Sendable` invariants unless the coordinator is itself an actor (which would
  replicate `OpenTabsActor`'s role).
- Option C couples two surfaces through `NotificationCenter`, a dynamic dispatch
  mechanism that cannot be checked at compile time and breaks under Task cancellation.

### Invariant

> **`SidebarTreeViewModel.selectedNode` is always derived from
> `OpenTabsActor.activeTabId`. It is never set independently of an actor broadcast.**

Corollary — the only two mutating call sites for `selectedNode` are:

1. `subscribeToOpenTabs()` — assigns the derived `SidebarNode` when
   `OpenTabsActor` emits a new snapshot. This is the authoritative write path.
2. `activate(_:)` — assigns `selectedNode` eagerly on user tap for instant visual
   feedback before the actor round-trip completes. The actor broadcast that follows
   produces an identical value, so the eager write is idempotent.

Call sites that do NOT set `selectedNode` directly: `TabBarView`, any view that
calls `openTabs.openTab(_:)` without going through the sidebar.

### Implementation

`SidebarTreeViewModel.start()` spawns `subscribeToOpenTabs()` as a concurrent child
task using `async let _ = subscribeToOpenTabs()`. The child task runs for the lifetime
of `start()` (which is infinite, bound to `clusterStrip.stateStream()`).

```swift
private func subscribeToOpenTabs() async {
    for await snapshot in openTabs.stateStream() {
        guard let activeId = snapshot.activeTabId,
              let activeTab = snapshot.tabs.first(where: { $0.id == activeId })
        else { continue }
        let derived = SidebarNode.from(documentTab: activeTab)
        if derived != selectedNode {
            selectedNode = derived
        }
    }
}
```

`SidebarNode.from(documentTab:)` maps every `DocumentTab` leaf case to its
corresponding `SidebarNode` leaf. Tabs with no sidebar representation (detail views,
log streams, exec sessions, port-forwards) return `nil`, leaving `selectedNode`
unchanged — the sidebar continues to show the last meaningfully highlighted row.

### Forward direction (sidebar tap → tab open)

```swift
public func activate(_ node: SidebarNode) async {
    selectedNode = node          // eager: instant visual feedback
    guard let clusterId = activeClusterId,
          let tab = node.toDocumentTab(clusterId: clusterId) else { return }
    await openTabs.openTab(tab)  // actor broadcasts → subscribeToOpenTabs fires
}
```

`openTab(_:)` deduplicates by `TabId` — if the tab is already open it only calls
`focusTab(_:)`, which still broadcasts. The sidebar subscription then re-derives
`selectedNode`, producing the same value as the eager write. The double write is
safe: `@Observable` coalesces identical writes into zero view updates.

### Inverse mapping (`SidebarNode.from(documentTab:)`)

Defined as a static method on `SidebarNode` in `Sources/AppShell/Domain/SidebarTree.swift`.
Returns `nil` for tabs that have no sidebar leaf (editor, logs, exec, debug, portForward,
diagnostics, welcome). The nil case is intentional: the operator opened a secondary surface
that is not a primary sidebar entry, so the sidebar retains the last meaningful row highlight.

### Consequences

Positive:

- Sidebar highlight is always consistent with the tab bar active chip after the first
  actor broadcast, eliminating the frame 14 desync class.
- New features that open tabs programmatically (command palette, drawer buttons, keyboard
  shortcuts) automatically keep the sidebar in sync with zero additional code.
- `SidebarTreeViewModel` has no direct dependency on `TabBarViewModel` — the coupling
  is mediated entirely by `OpenTabsPort`.

Negative:

- Eager write in `activate(_:)` followed by actor-broadcast re-derive produces two
  consecutive writes to `selectedNode`. The second write is a no-op in `@Observable`
  terms (identical value, no view update) but adds one extra comparison per tap.
- Tabs with no sidebar mapping (`nil` from `SidebarNode.from`) leave the sidebar
  frozen on the last meaningful row. Some operators may find this confusing when
  opening a detail view or log stream. This is accepted behaviour documented here
  as a design choice, not a bug.

## Confirmation

- `Sources/AppShell/ViewModels/SidebarTreeViewModel.swift` — `start()` spawns
  `subscribeToOpenTabs()` as a concurrent child; `subscribeToOpenTabs()` derives
  `selectedNode` from each `OpenTabsSnapshot`.
- `Sources/AppShell/Domain/SidebarTree.swift` — `SidebarNode.from(documentTab:)`
  provides the exhaustive inverse mapping.
- `Sources/AppShell/ViewModels/SidebarTreeViewModel.swift` — `activate(_:)` eagerly
  sets `selectedNode` then dispatches `openTabs.openTab(_:)`.

## More information

- ADR-0034 — State-driven realtime UI; derived state via `AsyncStream` is the canonical
  pattern for keeping two surfaces in sync.
- ADR-0050 — Resource navigation taxonomy; `OpenTabsActor`, `TabId`, and `DocumentTab`
  are defined here; `SidebarNode.toDocumentTab(clusterId:)` is the forward mapping.
- ADR-0052 — CRD dynamic sidebar nodes; dynamic `customResourceKind` leaves follow the
  same derived-selection invariant via `SidebarNode.from`.
