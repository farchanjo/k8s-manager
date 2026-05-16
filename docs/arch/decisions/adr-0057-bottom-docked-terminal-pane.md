# ADR-0057 — Bottom-docked terminal pane with node-debug shell integration

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0017 (terminal sessions: pod exec and node debug), ADR-0021 (app shell design system
  and main layout), ADR-0050 (resource navigation taxonomy and multi-document tab system),
  ADR-0051 (multi-cluster workspace: cluster strip, provider grouping, chrome layout)
- Tags — terminal, bottom-pane, node-debug, app-shell, multi-tab

## Context and problem statement

ADR-0017 established the terminal session model: each `pods/exec` or `nodes/debug` session is owned
by a `TerminalSessionActor` and is surfaced to the operator as a dedicated `DocumentTab` in the tab
bar (ADR-0050). This model works well for long-running sessions that the operator wants to keep open
alongside other resource tabs. However, the reference recording (`Screen Recording 2026-05-16 at
13.19.58.mov`, Lens × Mirantis Desktop, items R7/R35/R36/R37 in
`docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`) shows a different terminal
interaction pattern that the dedicated-tab model cannot satisfy:

1. The operator is working in a Nodes list or a Node detail drawer and wants to open a quick shell
   to the selected node without losing sight of the list or the drawer.
2. Multiple short-lived exec sessions (pod-exec, node-debug) need to coexist as tabs within a
   shared bottom panel, not as top-level tabs that displace the active resource view.
3. The panel must be slideable, resizable, and fullscreen-capable without disturbing the layout of
   the resource list or the detail drawer above it.

The existing `TerminalSessionView` tab approach forces the operator to navigate away from the
resource context to interact with the terminal. A bottom-docked pane resolves this by occupying a
separate vertical region beneath the content area, enabling simultaneous visibility of the resource
list and the terminal session.

This ADR defines:

- The layout position and chrome of the bottom-docked terminal pane.
- The `DockedTerminalTab` identity model.
- The relationship between the docked pane and the existing `TerminalSessionView` tab.
- The "Shell to Node" entry point from `ResourceDetailDrawer` for the Node kind.
- The connection state banner.
- Pane-state persistence in the workspace.

## Decision drivers

- **Resource-list context preservation** — operators performing ad-hoc node debugging or pod
  introspection must not lose the list view or the detail drawer state when opening a terminal.
- **Multi-session visibility** — multiple PTY sessions (pod-exec on one pod, node-debug on another
  node, container-exec on a second container) must be simultaneously accessible without navigating
  between top-level tabs.
- **Fullscreen escape hatch** — operators who need deep terminal work must be able to expand the
  docked pane to fill the content area without permanently displacing other views.
- **Minimal layout regression** — the docked pane must not interfere with the cluster strip
  (ADR-0051 §Chrome layout, vertical cluster strip), the sidebar tree, or the detail drawer.
- **Alignment with the existing terminal session model** — `TerminalSessionActor` (ADR-0017) must
  remain the session owner; the docked pane is a presentation layer, not a new session transport.

## Considered options

- **Option A** — Collapse the existing `TerminalSessionView` dedicated tab into the docked pane
  exclusively. Terminal sessions only exist in the docked pane; the top-level tab type is removed.
- **Option B** — Keep both: top-level `TerminalSessionView` tab for long-running sessions initiated
  from the tab bar, and a docked pane for quick ad-hoc sessions opened from resource detail actions.
  Both share the `TerminalSessionActor` transport layer.
- **Option C** — Docked pane only, with workspace-state persistence and a "promote to tab" action
  that moves a docked session into a full top-level tab when the operator needs persistent
  side-by-side navigation.

## Pros and cons of the options

### Option A — Docked pane only, no dedicated terminal tab

- Good, because there is a single terminal surface; operators cannot accidentally have sessions split
  across two presentation models.
- Bad, because long-running sessions (overnight log tail, extended node debugging) lose the
  persistent multi-document tab identity (tab restore across launches, cross-cluster coexistence in
  the tab bar). ADR-0050 persistence guarantees apply to top-level tabs; the docked pane has a
  separate and narrower persistence model.
- Bad, because removing the terminal tab type is a breaking change to the existing `OpenTabsActor`
  domain model and all Gherkin that covers terminal tabs.

### Option B — Both: dedicated tab for long-running, docked pane for ad-hoc (chosen)

- Good, because the two surfaces serve genuinely distinct intents: the dedicated tab serves
  long-running, tab-bar-navigable sessions (e.g., a log-tail or a monitoring shell kept open across
  cluster switches); the docked pane serves quick ad-hoc sessions opened from resource actions where
  losing the list context would cost the operator more than a PTY session is worth.
- Good, because neither the existing `OpenTabsActor` domain model nor the terminal Gherkin require
  breaking changes. The docked pane adds a new surface; it does not retire the old one.
- Good, because the `TerminalSessionActor` transport layer is shared: docked and tab sessions are
  both backed by `URLSessionWebSocketTask` with `v5.channel.k8s.io` negotiation (ADR-0017 §Protocol
  detail). Presentation differences are confined to the view layer.
- Bad, because operators must understand which surface to use. The application must communicate the
  distinction through affordances (the docked pane's "Shell to Node" and "Shell to Pod" entry points
  vs the sidebar-tree terminal entry point that opens a dedicated tab).

### Option C — Docked pane only with "promote to tab" action

- Good, because it unifies the initial entry point (always docked) while preserving the long-running
  tab use case via promotion.
- Bad, because "promote to tab" is a stateful action that requires migrating live PTY state across
  two presentation layers at runtime, which introduces session-teardown risk during the transition.
- Bad, because the promotion gesture is not surfaced in the reference recording and would be a
  K8S-Manager-specific pattern with no prior art in the Lens reference.

## Decision outcome

**Option B is adopted.** The bottom-docked terminal pane and the existing `TerminalSessionView`
dedicated tab coexist. The docked pane is the preferred entry point for resource-action-triggered
sessions (node debug shell, pod exec from the detail drawer). The dedicated tab remains the
preferred surface for long-running sessions opened through the sidebar tree terminal entry point.

### Bottom pane chrome

The docked terminal pane occupies a horizontal region at the bottom of the content area, below the
resource list and above the status bar. It is rendered outside the `NavigationSplitView` columns,
in the same `AppShell` composition layer as the cluster strip (ADR-0051 §Chrome layout).

Chrome elements, from top to bottom and left to right:

- **Drag-resize handle** — a 4 pt tall horizontal divider at the top edge of the pane. The operator
  drags this handle to resize the pane height. A double-click on the handle resets the height to the
  default (33% of the content area height, rounded to the nearest point). Minimum pane height is
  120 pt. Maximum pane height is 80% of the content area height. Resize is animated with a
  spring-damped transition (duration 0.18 s, stiffness 320, damping 28).
- **Tab bar row** — a horizontal row at the top of the pane interior, immediately below the resize
  handle. Contains:
  - One tab button per open `DockedTerminalTab`, in open order (most recently opened rightmost).
  - Each tab button shows the session label (e.g., `Node: worker-01`, `Pod: api-server-abc12`),
    a per-tab close `X` button on the right, and a connection state indicator dot (green/amber/red).
  - An `+` button at the right end of the tab row opens a new ad-hoc shell (kind `container-exec`)
    for the currently active cluster's first reachable pod.
  - A search toggle `Aa /.*/` at the far right of the tab row opens a search-in-output toolbar for
    the active tab. The `Aa` toggle enables case-sensitive matching; `/.*/` enables regex mode.
  - A fullscreen toggle button (chevrons icon) at the far right expands the pane to fill the full
    content area height (status bar excluded). A second press collapses back to the persisted height.
- **PTY viewport** — the terminal emulator surface, below the tab bar row. Each tab's PTY is
  rendered independently; switching tabs swaps the viewport without tearing down the underlying
  `TerminalSessionActor`.

The pane is hidden (zero height, not removed from the view hierarchy) when there are no open
`DockedTerminalTab` instances. The pane slides into view (spring animation matching the drag-resize
spring) when the first docked tab is opened.

### DockedTerminalTab identity

`DockedTerminalTab` is a value type (Swift `struct` conforming to `Identifiable`) that represents
one PTY session hosted in the docked pane.

Fields:

- `id: UUID` — stable identity across view updates.
- `kind: DockedTerminalKind` — one of `podExec`, `nodeDebug`, `containerExec`.
- `sessionActorId: UUID` — the `id` of the backing `TerminalSessionActor` instance.
- `label: String` — display label shown in the tab bar (e.g., `Node: worker-01`).
- `clusterId: ClusterId` — the cluster this session belongs to. Ensures that cluster strip switching
  does not silently attach an active session to the wrong cluster context.
- `connectionState: TerminalConnectionState` — mirror of the `TerminalSessionActor`'s lifecycle
  state (`opening`, `open`, `closing`, `closed`, `error`), used to drive the per-tab indicator dot.

`DockedTerminalPane` (Swift actor) owns the ordered list of `DockedTerminalTab` values and exposes
an `AsyncStream<[DockedTerminalTab]>` consumed by `DockedTerminalPaneViewModel`. It does not own the
`TerminalSessionActor` instances themselves; those remain in `TerminalSessionManager` (ADR-0017).

### Node debug shell flow

The "Shell to Node" entry point is a link-style button placed in the `ResourceDetailDrawer` header
action bar when the selected resource kind is `Node`.

Flow:

1. The operator opens `ResourceDetailDrawer` for a Node resource (any of the standard paths:
   clicking a Node row, navigating from the sidebar tree).
2. The header action bar shows a `Shell to Node: <nodeName>` link button alongside the standard
   Edit YAML, Delete, and Events actions.
3. Tapping the button triggers `NodeDebugViewModel.beginDebugSession(node:)` (existing view model,
   already present in `AppShell/ViewModels/NodeDebugViewModel.swift`).
4. `NodeDebugViewModel` issues the `nodes/debug` Pod creation (ADR-0017 §Decision outcome, `nodes/debug`
   path), then opens a WebSocket exec session on the ephemeral Pod via `TerminalSessionActor`.
5. `DockedTerminalPane` receives the new session ID and inserts a `DockedTerminalTab` with
   `kind: nodeDebug`, `label: "Node: <nodeName>"`, `connectionState: .opening`.
6. The docked pane slides up if it was hidden.
7. The connection state banner (see §Connection state banner below) is shown inside the PTY viewport
   of the new tab until the session reaches `open` state.
8. Once `open`, the banner is removed and the live PTY is presented.

The operator remains on the Node detail drawer and the resource list throughout this flow; no
navigation away from the current context occurs.

The node debug session is a mutating operation (ADR-0012): before step 3, the application presents
the ADR-0012 confirmation sheet ("This will create an ephemeral debug pod on node <nodeName>. Do
you want to continue?"). The operator must confirm before `NodeDebugViewModel.beginDebugSession`
executes.

### Connection state banner

While a `DockedTerminalTab` is in `opening` or `closing` state, the PTY viewport for that tab
shows a full-width status banner with three progressive states:

- **Initial** — `Shell to Node: <nodeName>` (or `Shell to Pod: <podName>` for pod-exec sessions).
  Shown immediately on tab open, before any network activity.
- **Connecting** — `Connecting …` with a spinner. Shown once the `TerminalSessionActor` has
  dispatched the WebSocket handshake (or, for node debug, once the ephemeral Pod creation request
  has been issued).
- **Live PTY** — banner removed; PTY viewport takes full height. Transition is instant (no
  animation) to avoid obscuring the first terminal output lines.

For `error` state: the banner shows `Connection failed: <human-readable reason>` in the warning
colour token (`statusError` from the design token palette, ADR-0021 §Design tokens). A `Retry`
button re-initiates `NodeDebugViewModel.beginDebugSession` or `TerminalSessionActor.reconnect`
as appropriate. For `closed` state after clean session end: the banner shows `Session closed` with
a `Reopen` button.

### Persistence

The docked pane state is persisted per-workspace (one workspace maps to one window, ADR-0026):

- **Persisted**: pane height (in points), open tab list with `DockedTerminalTab.id`,
  `DockedTerminalTab.kind`, `DockedTerminalTab.label`, `DockedTerminalTab.clusterId`.
- **Not persisted**: `sessionActorId` (actors are not re-hydrated after launch), PTY output buffer
  (ADR-0017 §Decision drivers, "No stdout persistence"), connection state.
- On cold launch with a persisted tab list: each tab is restored in the closed state with a `Reopen`
  banner. The `TerminalSessionActor` is not started until the operator taps `Reopen`. This avoids
  automatic ephemeral-Pod creation on every launch.

Persistence path: `~/Library/Application Support/K8sManager/workspace/docked-terminal-pane.json`.
The file uses the same JSON encoding conventions as `cluster-strip-pins.json` (ADR-0051
§ClusterStripPin schema). The path is added to the ADR-0026 filesystem layout addendum.

## Confirmation

- CUE schema `contexts/app_shell/schemas/docked_terminal_pane.cue` defines `#DockedTerminalTab`,
  `#DockedTerminalKind`, and `#DockedTerminalPaneState` and is validated in CI via `cue vet`.
- Rego policy `contexts/app_shell/policies/docked_terminal_policy.rego` enforces:
  pane height within `[120, contentAreaHeight * 0.8]`; at most one `nodeDebug` tab per Node name
  per cluster; `clusterId` must reference a pinned cluster.
- Gherkin feature `contexts/app_shell/features/bottom-docked-terminal-pane.feature` covers the five
  scenarios described in this ADR.
- `NodeDebugViewModel` is extended with a `dockedPaneTarget: DockedTerminalPane` dependency injected
  via `AppShellDependencies`, enabling unit tests to assert that a successful debug session inserts
  the expected `DockedTerminalTab`.
- An integration test verifies that after cold launch with a persisted two-tab docked pane state,
  both tabs are rendered in `closed` state and neither `TerminalSessionActor` is started until the
  operator taps `Reopen`.

## Followups

- ADR-0058 — Embedded Prometheus charts in the resource detail drawer. The Node detail drawer will
  host both a `MetricChart` section (ADR-0058) and the "Shell to Node" action button (this ADR).
  The two must be positioned without visual conflict in the drawer header action bar.
- ADR-0064 — Inline docked YAML editor pane. If both the terminal pane (bottom of content area) and
  the YAML editor pane (also described as bottom-split in the feature gap analysis) are visible
  simultaneously, the layout must define a stacking order or a mutual-exclusion rule. Defer to
  ADR-0064.
- Investigate whether the `DockedTerminalPane` actor should emit its `AsyncStream` on the
  `MainActor` directly (following the pattern of `ClusterStripActor`) or whether it should emit
  on a background actor and the view model hops to `MainActor`. Align with the actor-stream
  convention established by `ClusterStripActor` in ADR-0051.

## More information

- ADR-0017 — Terminal sessions; `TerminalSessionActor`, WebSocket transport, lifecycle state
  machine, node debug Pod creation.
- ADR-0021 — App shell design system; design token palette, status bar, `NavigationSplitView`
  three-column layout.
- ADR-0026 — State persistence and filesystem layout; workspace persistence path conventions.
- ADR-0050 — Resource navigation taxonomy; `DocumentTab`, `OpenTabsActor`, tab persistence.
- ADR-0051 — Multi-cluster workspace; cluster strip, detail drawer chrome, `AppShell` composition.
- Feature gap analysis — `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`,
  items R7, R35, R36, R37.

## Amendments

### Amendment 1 — Docked terminal pane renders as bottom-sheet overlay (2026-05-16)

The §Bottom pane chrome clause "The docked terminal pane occupies a horizontal region at the bottom
of the content area, below the resource list and above the status bar" is superseded by ADR-0072
(Apple-native window chrome consolidation), Change 5.

The terminal pane is now rendered as a floating `.overlay(alignment: .bottom)` sheet anchored to
the bottom of the content area column. It does not displace the resource list above it; it floats
over the content. Maximum pane height is capped at 50% of the content area height (reduced from the
80% cap in §Pane chrome). The drag-resize handle, tab bar row, PTY viewport, and persistence
contract are unchanged. The `DockedTerminalPane` actor is unaffected.

Forward reference: ADR-0072 (Change 5 — docked panes become bottom-sheet overlays).
