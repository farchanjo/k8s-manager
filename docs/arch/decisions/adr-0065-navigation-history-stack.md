# ADR-0065 — Navigation history stack

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0023 (UX patterns: command palette and keyboard shortcuts),
  ADR-0050 (resource navigation taxonomy), ADR-0051 (multi-cluster workspace)
- Tags — navigation, history, back-forward, app-shell, multi-document-tabs

## Context and problem statement

The feature-gap analysis against the Lens × Mirantis Prism AI reference recording (item R4) identifies
browser-style back/forward navigation arrows in the top-left chrome as a MISSING capability. The
current application has no history stack: navigating from a Deployment list to a Pod detail and back
requires the operator to retrace every sidebar selection manually. This causes regret-recovery
friction in drill-down workflows (e.g., follow an owner reference chain, inspect a failing Pod, then
back out to the Deployment list).

ADR-0023 registers the keyboard bindings `⌘[` and `⌘]` for history navigation and names a
`NavigationHistoryService` value object with a bounded stack of 100 entries. That ADR defines the
entry shape in the context of the command palette shortcut vocabulary but does not specify the owning
actor, the push/suppress rules, persistence strategy, cross-tab behaviour, or the UI affordance
(the back/forward arrow buttons themselves). This ADR closes those gaps.

## Decision drivers

- **Regret recovery** — operators who drill into a resource detail via an owner-reference chain or a
  sidebar click must be able to back out one step at a time without losing their previous list scroll
  position or selected row.
- **Drill-down / back-out patterns** — production workflows commonly traverse three to five levels
  (namespace filter → Deployment list → Pod list → Pod detail → container logs). Each level must be
  individually reachable via `⌘[`.
- **Multi-tab coherence** — the application supports multiple `DocumentTab` instances
  (ADR-0050) that may belong to different clusters. A naive single history list would confuse
  operators by unexpectedly switching the active tab during back/forward traversal. The chosen model
  must make cross-tab navigation legible and predictable.
- **Mental model simplicity** — the model chosen must match the established browser metaphor. Web
  browsers maintain a per-window history that covers all tabs; this is the baseline expectation for
  operators familiar with Chrome and Safari.
- **Persistence on relaunch** — operators expect the application to restore recent navigation state
  on cold launch, at least partially, so a long investigation session can be resumed.
- **Swift concurrency safety** — the history state must be owned by a dedicated actor to prevent
  shared mutable state across the SwiftUI view hierarchy.

## Considered options

- **Option A** — Per-tab history: each `DocumentTab` maintains its own independent history deque.
  Back/forward is scoped strictly to the active tab.
- **Option B** — Per-window single history (chosen): one `NavigationHistoryActor` per window owns
  the ordered history deque across all tabs. Back can switch the active tab if the previous entry
  belongs to a different tab.
- **Option C** — Per-cluster history: one history deque per cluster session, shared across all tabs
  belonging to that cluster.

## Decision outcome

Chosen option — **Option B — per-window single history**, because:

- The browser metaphor that R4 references is per-window. Back/forward arrows in Chrome, Safari, and
  Firefox operate on a window-level history that traverses across tabs. Operators already have this
  mental model.
- Option A (per-tab) requires the operator to remember which tab they were on before navigating to a
  detail view. When the detail opens in the same tab, per-tab history is adequate; but when
  navigation crosses tabs (e.g., following a cross-cluster owner reference), per-tab history
  silently loses the cross-boundary step.
- Option C (per-cluster) is redundant when the application has one active cluster session
  (ADR-0025 transitional state) and introduces ambiguity when cross-cluster tabs coexist, because a
  history entry from cluster A cannot be filed under cluster B.
- The per-window model is the simplest to reason about: one actor, one deque, one pair of arrow
  buttons.

### NavigationHistoryActor contract

`NavigationHistoryActor` is a Swift `actor` declared in the `app_shell` bounded context. It is the
aggregate root for navigation history state within a single window.

Responsibilities:

- Owns an ordered `[NavigationEntry]` deque (back stack + forward stack modelled as a cursor over a
  flat array).
- Maximum deque capacity: 100 entries. When a push would exceed capacity, the oldest entry at index
  0 is evicted (LRU pruning from the leading end).
- Exposes the cursor position as a published value so the back/forward arrow buttons can reflect
  enabled/disabled state reactively.
- Handles `push(_:NavigationEntry)`, `back() -> NavigationEntry?`,
  `forward() -> NavigationEntry?`, and `clear()` commands.
- On `push`, truncates any forward entries beyond the current cursor (standard browser behaviour:
  navigating forward after a back discards the now-stale forward chain).
- Persists the history deque to the workspace JSON (see persistence section) on every mutation,
  debounced 500 ms, matching the `OpenTabsActor` debounce pattern from ADR-0050.

### NavigationEntry value object

`NavigationEntry` is a `Sendable` value type (struct). Fields:

- `id` — UUIDv7 string; unique identifier for deduplication and persistence.
- `timestamp` — `Date`; wall-clock time of the navigation event.
- `clusterId` — `String` (UUIDv7); the cluster context active at the time of navigation.
- `tabId` — `String` (UUIDv7); the `DocumentTab.tabId` that was active.
- `kind` — `NavigationEntryKind` enum: `resourceList`, `resourceDetail`, `clusterOverview`,
  `helmReleases`, `helmDetail`, `events`, `terminalSession`. Mirrors `TabKind` from ADR-0050.
- `namespace` — `String?`; the active namespace filter at the time of navigation, `nil` for
  cluster-scoped entries.
- `selectedResourceName` — `String?`; the name of the resource row selected in the list view, `nil`
  when the entry records a list-level navigation with no row selected.
- `drawerSectionAnchor` — `String?`; the scroll anchor of the detail drawer section in focus (e.g.,
  `"properties"`, `"events"`, `"containers"`), `nil` when the detail drawer was closed.
- `viewportScrollOffset` — `CGFloat`; the vertical scroll offset of the content list at the time of
  navigation. Used to restore list position on back/forward. Defaults to 0.

### Push rules

A `NavigationEntry` is pushed onto the history stack when any of the following events occur:

- The operator selects a row in any resource list view (selecting a different row in the same list
  is a push; re-selecting the same row is suppressed).
- A new `DocumentTab` is opened from any source (sidebar click, command palette, programmatic open).
- The active `DocumentTab` changes (tab focus switch).
- The detail drawer scroll anchor changes to a different named section (e.g., scrolling from
  `"properties"` to `"events"` in the detail drawer).
- The active namespace filter changes for a list view.

### Suppress rules

A push is suppressed (no entry recorded) when:

- The navigation is a programmatic restore triggered by `back()` or `forward()` traversal. Restoring
  a previous entry must never create a new entry; doing so would corrupt the deque.
- The application is restoring persisted history on cold launch. The actor enters a `isRestoring`
  guard flag during restoration and clears it when done.
- The new entry would be identical to the current cursor entry (same `clusterId`, `tabId`, `kind`,
  `namespace`, `selectedResourceName`, `drawerSectionAnchor`). Duplicate suppression prevents
  thrashing from reactive SwiftUI re-renders.
- A `DocumentTab` of kind `terminalSession` is active. Terminal interaction (keystrokes, scroll)
  does not generate history entries; only the act of opening or closing the terminal tab does.

### Back/forward primitives

`back()`:

- Moves the cursor one position toward the beginning of the deque.
- Returns the `NavigationEntry` at the new cursor position, or `nil` if already at the oldest entry.
- The caller (the view layer) applies the entry: restores `selectedResourceName`, scroll offset,
  drawer section anchor, and (if `tabId` differs from the active tab) focuses the correct tab.
- Focus-restore transition: a 180 ms spring animation (`response: 0.18, dampingFraction: 0.82`)
  matches the palette open/close animation established in ADR-0023. Suppressed when
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` returns `true`.
- Keyboard shortcut: `⌘[` (registered in ADR-0023 global Cmd bindings table; this ADR is the
  authoritative implementation spec).

`forward()`:

- Moves the cursor one position toward the end of the deque.
- Returns the `NavigationEntry` at the new cursor position, or `nil` if at the newest entry.
- Keyboard shortcut: `⌘]`.

Both primitives are disabled (buttons greyed out, shortcut no-ops) during an active palette overlay
session and while the YAML editor has unsaved changes, matching the ADR-0023 suppression rules for
the `⌘[` / `⌘]` bindings inside the editor.

### Cross-tab navigation

When `back()` returns an entry whose `tabId` differs from the currently active tab:

1. `OpenTabsActor.focusTab(tabId:)` is called to switch the active tab.
2. The content list in the now-active tab is scrolled to `viewportScrollOffset`.
3. If `selectedResourceName` is non-nil and present in the current list data, the row is
   re-selected and the detail drawer is opened at `drawerSectionAnchor`.
4. If the tab referenced by `tabId` no longer exists (closed since the entry was recorded), the
   entry is skipped and `back()` continues to the next older entry. A maximum of 5 consecutive
   skip steps are attempted before halting.

### History persistence

- Scope: per-window. Stored alongside the workspace JSON managed by ADR-0026.
- Path: `~/Library/Application Support/K8sManager/workspace/navigation-history.json`.
- Schema defined in `contexts/app_shell/schemas/navigation_history.cue` (`#NavigationEntry`,
  `#NavigationHistoryState`), validated in CI via `cue:vet`.
- On persist: the full deque up to the current cursor is written (forward entries beyond the cursor
  are discarded on persist; they are ephemeral within a session only).
- On cold launch: the most recent 50 entries are restored. Entries older than 50 are not loaded,
  keeping cold-launch restoration fast and the initial deque within the 100-entry cap.
- Entries referencing a `clusterId` for which no active cluster session exists on launch are retained
  in the deque but treated as `skipOnRestore: true`; they remain traversable within the session once
  that cluster is reconnected.

### UI affordance

Two arrow buttons are placed in the top-left area of the window toolbar (left of the cluster strip,
mirroring R4 of the reference recording):

- Back arrow: SF Symbol `chevron.backward`, enabled when `cursorIndex > 0`.
- Forward arrow: SF Symbol `chevron.forward`, enabled when `cursorIndex < deque.count - 1`.
- Both buttons carry `accessibilityLabel("Navigate back")` / `accessibilityLabel("Navigate forward")`
  and expose `accessibilityKeyboardShortcut("⌘[")` / `accessibilityKeyboardShortcut("⌘]")`.
- Tooltip on hover: "Back (⌘[)" / "Forward (⌘])".

### Consequences

Positive:

- Operators can retrace drill-down paths (e.g., namespace → Deployment → Pod → container) without
  retracing sidebar selections manually.
- The browser metaphor is immediately familiar; no new interaction concept needs to be learned.
- Per-window scope keeps the mental model simple: one back button, one history.
- Cross-tab back/forward makes owner-reference drill-down across tabs recoverable.

Negative:

- `NavigationHistoryActor` is a new shared actor; it must be injected at the `AppShell` composition
  root and threaded to every view that issues navigation events, increasing dependency surface.
- Skipping over entries for closed tabs (`tabId` not found) adds edge-case logic that must be
  covered by unit tests.
- The LRU pruning policy (evict oldest on overflow) means very long sessions can silently lose early
  navigation context. The 100-entry cap is a pragmatic trade-off; it is not surfaced to the operator.
- Persistence of navigation history to disk introduces a new file in the workspace JSON subtree; it
  must be excluded from any workspace export that should not carry operator-session metadata.

## Pros and cons of the options

### Option A — Per-tab history

- Good, because back/forward is strictly scoped to the current tab; no unexpected tab switches.
- Good, because per-tab history state can be stored directly on `DocumentTab` without a new actor.
- Bad, because cross-tab drill-down (follow an owner reference that opens a new tab) is not
  recoverable; the entry does not exist in either tab's history.
- Bad, because the mental model diverges from browsers — operators expect `⌘[` to work regardless
  of which tab they are on.

### Option B — Per-window single history (chosen)

- Good, because the browser mental model transfers directly; one back button covers all tabs.
- Good, because cross-tab entries are naturally preserved.
- Good, because a single `NavigationHistoryActor` is straightforward to inject and test.
- Bad, because back can switch the active tab, which may surprise operators who do not realise they
  navigated across tabs.

### Option C — Per-cluster history

- Good, because history is bounded to a single cluster, avoiding cross-cluster confusion.
- Bad, because cross-cluster owner references are not recoverable.
- Bad, because the current transitional state (ADR-0050 addendum: single process-wide tab list)
  makes per-cluster history storage premature until `OpenTabsRegistry` lands.

## Confirmation

- `contexts/app_shell/schemas/navigation_history.cue` defines `#NavigationEntry` and
  `#NavigationHistoryState` and is validated in CI via `cue:vet`.
- Rego policy `contexts/app_shell/policies/navigation_history_policy.rego` enforces invariants:
  cursor index must be within deque bounds; every entry must carry a non-empty `id`; deque length
  must not exceed 100.
- Gherkin feature `contexts/app_shell/features/navigation-history-back-forward.feature` covers:
  back restores previous resource selection, forward re-applies, back across tabs switches active
  tab, keyboard dispatch `⌘[` / `⌘]`, history persistence across launch (50 entries).
- A unit test for `NavigationHistoryActor` verifies that pushing 101 entries evicts entry 0 and
  retains entries 1–100.
- A unit test verifies that calling `back()` does not push a new entry.
- An integration test restores 5 persisted entries on cold launch, calls `back()` twice, and asserts
  the correct `NavigationEntry` is returned each time.
- `workspace.dsl` registers `NavigationHistoryActor` as a component of the `App Shell` container
  with a dependency on `OpenTabsActor` (for cross-tab focus) and `WorkspacePersistencePort` (for
  history JSON persistence).

## More information

- ADR-0023 — UX patterns: command palette and keyboard shortcuts; registers `⌘[` / `⌘]` bindings
  and the `NavigationHistoryService` stub. This ADR supersedes the stub with a full actor contract.
- ADR-0025 — Per-cluster isolation; `ClusterSessionActor` is referenced by `clusterId` in each
  `NavigationEntry`.
- ADR-0026 — State persistence; navigation history persistence path added to the workspace subtree.
- ADR-0050 — Resource navigation taxonomy; `DocumentTab` and `OpenTabsActor` are consumed by
  `NavigationHistoryActor` for cross-tab focus restoration.
- ADR-0051 — Multi-cluster workspace; the cluster strip and tab bar are the primary navigation
  surfaces whose state changes generate history entries.
- Feature gap analysis `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`,
  item R4 — browser-style back/forward arrows: the direct trigger for this ADR.

## Amendments

### Amendment 1 — Nav arrows promoted to window toolbar `.navigation` placement (2026-05-16)

The §UI affordance clause "Two arrow buttons are placed in the top-left area of the window toolbar
(left of the cluster strip, mirroring R4 of the reference recording)" is superseded by ADR-0072
(Apple-native window chrome consolidation), Change 2.

The `SidebarCanvasView.headerBar` in which the arrows previously resided is removed entirely by
ADR-0072. The back and forward `ToolbarItem` declarations (SF Symbols `chevron.backward` and
`chevron.forward`, placement `.navigation`) are now registered at the primary window's `.toolbar {}`
block rather than inside the canvas header. The `NavigationHistoryActor` wiring, enabled/disabled
state logic, keyboard shortcuts `⌘[` / `⌘]`, accessibility labels, and tooltip text are unchanged.

Forward reference: ADR-0072 (Change 2 — nav arrows move to window toolbar `.navigation` placement).
