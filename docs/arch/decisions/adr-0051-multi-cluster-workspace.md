# ADR-0051 — Multi-cluster workspace: cluster strip, provider grouping, pinning, and chrome layout

- Status — Accepted (ratified 2026-05-16)
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0021 (app shell design system and main layout), ADR-0025 (per-cluster isolation
  strategy), ADR-0026 (state persistence and filesystem layout)
- Tags — ui, workspace, multi-cluster, cluster-strip, sidebar, chrome, pinning, persistence,
  app-shell

## Context and problem statement

ADR-0021 defined the primary window structure as a `NavigationSplitView` with three columns
(sidebar, content list, detail pane) plus an inspector panel and a status bar. The sidebar column
contained context navigation and application-level items as a flat list of bounded-context sections
(Clusters, Context, Resources, Assistant, Helm, Metrics, Port Forward, Terminal).

As the application grows to support simultaneous sessions across multiple clusters (ADR-0025), three
structural problems emerge with the ADR-0021 layout:

1. **Cluster switching is hidden** — the cluster picker lives inside the toolbar. Switching clusters
   requires a toolbar interaction that is not discoverable and does not communicate which clusters
   are currently active.

2. **Provider grouping is absent** — operators who manage clusters across AKS, EKS, GKE, and local
   kubeconfigs cannot distinguish provider context from the sidebar alone.

3. **The sidebar mixes navigation levels** — bounded-context sections (Helm, Metrics, Terminal) are
   at the same visual level as cluster-scoped resource categories (Workloads, Network), making the
   hierarchy unclear.

This ADR specifies a Lens IDE-inspired chrome layout that resolves all three issues: a vertical
cluster strip at the left extreme of the window, a per-cluster sidebar tree with provider grouping
and resource categories, a tab bar for multi-document navigation (ADR-0050), a detail drawer
replacing the inspector for resource metrics and actions, a status bar with cluster telemetry, and a
top-right chrome area for assistant and user controls.

## Decision drivers

- **Discoverability of active clusters** — the cluster strip must make all active (pinned) cluster
  sessions visible without any navigation action.
- **Provider identity** — operators who manage hundreds of clusters across cloud providers need
  provider-level grouping to locate the right cluster quickly.
- **Separation of navigation levels** — workspace-level (cluster strip) and cluster-level (sidebar
  tree) navigation must be visually distinct.
- **Lean on macOS native conventions** — the strip + sidebar pattern is used by Xcode (navigator
  groups), Instruments (track lanes), and third-party tools (Proxyman). It is established on macOS.
- **Persistence** — pinned cluster order and sidebar disclosure states must survive application
  restarts.
- **Swift concurrency safety** — the cluster strip state is owned by a dedicated actor to avoid
  shared mutable state across the view hierarchy.

## Considered options

- **Option A** — Cluster strip + per-cluster sidebar tree + tab bar + detail drawer (chosen).
- **Option B** — Toolbar cluster picker + flat sidebar sections (ADR-0021 extended, no strip).
- **Option C** — Tab-per-cluster with no sidebar tree (each cluster is a top-level tab, resource
  navigation happens within the tab content).

## Decision outcome

Chosen option — **Option A**, because:

- The cluster strip makes all pinned cluster sessions immediately discoverable without navigating.
- The per-cluster sidebar tree naturally accommodates provider grouping and resource categories.
- Option B cannot surface simultaneous cluster health without expensive toolbar popover design.
- Option C pushes all navigation into tab content, losing the persistent sidebar tree benefit and
  making keyboard-driven resource navigation impractical.

### Chrome layout specification

#### Vertical cluster strip (left extreme)

The cluster strip is a fixed-width column (52 pt) at the left edge of the window frame, outside the
`NavigationSplitView`. It is always visible; it cannot be collapsed.

Each pinned cluster session is represented by a circular avatar chip (36 pt diameter) containing:

- The cluster's initials (up to 2 characters, derived from the cluster display name).
- A background color deterministically assigned from a palette of 8 colors (hash of `clusterId`
  modulo 8).
- A status ring: green (healthy), amber (degraded), red (unreachable), grey (loading/unknown). The
  ring is 2 pt wide.
- A tooltip on hover showing the full cluster display name and connection state.

The active cluster chip has a filled rounded-rectangle background highlight in `accentBrand` at 20%
opacity. Clicking a chip switches the active cluster for the sidebar tree and the tab bar focus.

Pinned clusters are ordered by pin order (draggable). Un-pinned clusters do not appear in the strip.
A `+` button at the bottom of the strip opens the kubeconfig cluster picker (connects a new cluster
and pins it).

The cluster strip is drawn in a separate `NSView` layer outside the `NavigationSplitView` to avoid
interfering with column width calculations.

**Cluster strip state ownership** — `ClusterStripActor` owns the ordered list of `ClusterStripPin`
values. It exposes an `AsyncStream<[ClusterStripPin]>` consumed by the strip view model. The
`ClusterStripActor` persists the pin order to
`~/Library/Application Support/K8sManager/workspace/cluster-strip-pins.json` (path added to ADR-0026
addendum).

#### Per-cluster sidebar tree

The sidebar column (`NavigationSplitView` first column, 220–360 pt) renders the resource tree for
the active cluster. The tree is structured as follows:

```
[Provider section header — e.g. "AKS"]
  [Cluster display name]
    Overview
    Nodes
    Workloads
      Deployments
      StatefulSets
      DaemonSets
      ReplicaSets
      Pods
      Jobs
      CronJobs
      HorizontalPodAutoscalers
    Config
      ConfigMaps
      Secrets
      ServiceAccounts
      ...
    Network
      Services
      Ingresses
      NetworkPolicies
      ...
    Storage
      PersistentVolumes
      PersistentVolumeClaims
      StorageClasses
      ...
    Namespaces
    Events
    Helm
    Access Control
      Roles
      RoleBindings
      ClusterRoles
      ClusterRoleBindings
    Custom Resources
      [API group]
        [Kind]
```

Provider sections map to authentication methods:

- `AKS` — clusters whose kubeconfig exec block uses the Azure credential adapter.
- `EKS` — clusters using the AWS credential adapter.
- `GKE` — clusters using the GCP credential adapter.
- `OIDC` — clusters using the OIDC adapter.
- `Local Kubeconfigs` — all other clusters (static credential, client certificate, token).

Provider section headers are not clickable navigation targets; they are visual grouping labels only.
An operator can have zero or more clusters under each provider section. Empty provider sections are
hidden.

The sidebar tree is a read-only projection. It does not own cluster state; it reads from
`ClusterSessionActor` read models and `OpenTabsActor` state. Disclosure states (expanded/collapsed
per category) are persisted to the per-cluster view state JSON (ADR-0025, ADR-0026).

#### Detail drawer (slide-in right panel)

The detail drawer replaces the `NavigationSplitView` third column and the `.inspector` panel from
ADR-0021. The drawer slides in from the right edge of the content pane when a tab is open and a
resource is selected.

Drawer contents (in vertical order):

1. **Resource header** — kind badge, name, namespace, status chip, age.
2. **Action toolbar** — Edit YAML, Open Terminal (Pod/Node only), Rollout Restart (Deployment/
   StatefulSet/DaemonSet), Scale (Deployment/StatefulSet/ReplicaSet), Delete (with double-confirm
   per ADR-0012).
3. **Metrics panel** — Prometheus CPU/Mem sparklines (Pod, Node, Deployment). Hidden when Prometheus
   is not configured (ADR-0016).
4. **Properties grid** — read-only key/value pairs for the most-used fields. Expandable.
5. **Containers section** — container list with status, image, restart count. Pod only.
6. **Volumes section** — volume list with mount paths. Pod only.
7. **Events section** — last 20 Kubernetes events for the resource. Chronological, auto-refreshing.

The drawer width is fixed at 360 pt on first open; operators can drag-resize to 280–600 pt. Width is
persisted per kind in the per-cluster view state.

The drawer is toggled via the tab bar context menu, keyboard shortcut `⌘⇧I`, or clicking a resource
row. It does not replace the active tab; it is a parallel context pane.

#### Status bar (bottom, pinned)

The status bar layout is extended from ADR-0021 to carry cluster-specific telemetry:

- **Leading** — cluster display name + provider icon + context name.
- **Center-left** — Kubernetes version (e.g., `v1.31.2`).
- **Center** — CPU `%` / Mem `%` (node aggregate, 30 s auto-refresh from Prometheus if available).
- **Center-right** — watch streams active count (e.g., `3 watches`).
- **Trailing** — error count badge (red if > 0) + connection health icon.

The status bar reads from a `StatusBarReadModel` that aggregates from `ClusterSessionActor`,
`WatchStreamCoordinator`, and `metricsObservability`.

#### Top-right chrome

The top-right area of the unified toolbar carries:

- **Assistant AI toggle** (`⌘⇧A`) — opens the assistant chat panel as a sheet or splits the content
  pane horizontally. The panel mode is persisted in `window_layout.cue`.
- **Notifications dropdown** — bell icon; shows recent domain events (mutation confirmations, watch
  errors, CRD discoveries). Badge count reflects unread notifications.
- **User/preferences menu** — person icon; opens Settings (preferences, provider configuration,
  appearance, about).

### ClusterStripPin schema

`#ClusterStripPin` is defined in `contexts/app_shell/schemas/cluster_strip_pin.cue`:

```
clusterId: string (UUIDv7)
displayName: string
colorIndex: int (0–7)
pinOrder: int (≥0)
isPinned: bool
providerKind: "aks" | "eks" | "gke" | "oidc" | "local"
```

### Consequences

Positive:

- All active cluster sessions are always visible; switching clusters is a single click.
- Provider grouping enables operators to manage hundreds of clusters without losing context.
- The detail drawer consolidates metrics, properties, events, and actions in a single panel,
  reducing the need to navigate to separate views.
- The status bar telemetry gives instant health feedback for the active cluster.

Negative:

- The cluster strip requires a layout change outside `NavigationSplitView`, adding complexity to the
  window composition layer (`AppShell`).
- `ClusterStripActor` is a new shared actor with persistent state; it must be tested for
  concurrent-access correctness.
- The detail drawer's Prometheus embed creates a dependency on `metricsObservability` in the
  `AppShell` view layer; the dependency must not flow into domain-core targets.

## Pros and cons of the options

### Option A — Cluster strip + sidebar tree + tab bar + detail drawer (chosen)

- Good, because cluster sessions are always visible and switchable.
- Good, because provider grouping scales to large fleets.
- Good, because the detail drawer consolidates the inspector and the content list detail.
- Bad, because the cluster strip requires layout work outside the standard `NavigationSplitView`.

### Option B — Toolbar cluster picker + flat sidebar (ADR-0021 extended)

- Good, because it requires no new layout primitives.
- Bad, because the toolbar picker is hidden; operators must actively click to discover active
  sessions.
- Bad, because flat sidebar sections do not scale to 51 kinds or provider grouping.

### Option C — Tab-per-cluster

- Good, because it is conceptually simple (one tab = one cluster).
- Bad, because sidebar navigation within a cluster requires a nested navigation model that conflicts
  with the macOS `NavigationSplitView` paradigm.
- Bad, because keyboard navigation across clusters requires tab switching rather than sidebar
  navigation.

## Confirmation

- `contexts/app_shell/schemas/cluster_strip_pin.cue` defines `#ClusterStripPin` and
  `#ClusterStripState` and is validated in CI via `cue:vet`.
- Rego policy `contexts/app_shell/policies/tab_navigation_policy.rego` enforces cluster strip
  invariants: pin order must be unique; colorIndex must be 0–7.
- Gherkin features `cluster-strip-pin-unpin.feature` covers pin, unpin, drag-reorder, avatar color
  assignment, and status ring rendering.
- A unit test for `ClusterStripActor` verifies that adding a cluster assigns a deterministic color
  index and that removing all clusters leaves an empty pin list.
- An integration test restores a persisted cluster strip with 3 pins across different providers
  after a simulated cold launch and asserts that the strip renders in pin order with correct
  avatars.
- `workspace.dsl` registers `ClusterStripActor` (modelled as part of the `App Shell` container
  alongside `TabSessionManager`) with relationships to `ClusterSessionActor`.

## More information

- ADR-0021 — App shell design system; original `NavigationSplitView` 3-column layout. This ADR
  introduces the cluster strip as a fourth layout element outside those three columns.
- ADR-0025 — Per-cluster isolation; `ClusterSessionActor` provides health and session state read by
  the strip and sidebar.
- ADR-0026 — State persistence; cluster strip pin order persisted to `workspace/` subtree (addendum
  in ADR-0026).
- ADR-0050 — Resource navigation taxonomy; defines the sidebar category tree structure and tab
  system that the sidebar tree exposes.
- ADR-0052 — Custom resource discovery; defines how CRD groups appear in the sidebar tree Custom
  Resources section.

## Amendments

### Amendment 1 — ClusterStripView is now operator-toggleable; detail drawer retired (2026-05-16)

The clause "It is always visible; it cannot be collapsed." in §Vertical cluster strip is superseded
by ADR-0072 (Apple-native window chrome consolidation), Change 4.

`ClusterStripView` is now toggled via a window-toolbar button. Default state: visible
(`WindowLayout.mainWindow.clusterStripVisible = true`). When hidden, the active cluster context
remains accessible via a compact cluster avatar `ToolbarItem` in the window toolbar and the
keyboard shortcut `⌘⇧K`. This is a presentation-layer change only; `ClusterStripActor` and the
pin order persistence contract are unchanged.

Additionally, the §Detail drawer (slide-in right panel) specification is retired by ADR-0073
(Inspector trailing column). The detail drawer's content inventory migrates to per-kind
`ResourceInspectorContent` conformances rendered inside the `.inspector(isPresented:)` trailing
column. The `⌘⇧I` shortcut is reassigned to the Inspector toggle.

Forward references: ADR-0072 (Change 4), ADR-0073 (Inspector trailing column).
