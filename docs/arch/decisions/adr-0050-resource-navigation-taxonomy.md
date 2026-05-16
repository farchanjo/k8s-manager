# ADR-0050 — Resource navigation taxonomy: 51 standard Kubernetes kinds, CRD discovery, and multi-document tab system

- Status — Accepted (ratified 2026-05-16)
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0013 (resource browser scope and supported kinds), ADR-0021 (app shell design system
  and main layout), ADR-0034 (state-driven realtime UI architecture)
- Tags — resource-browser, navigation, taxonomy, kinds, tabs, multi-document, crd, sidebar

## Context and problem statement

ADR-0013 established a closed-set kind catalogue of 23 well-known Kubernetes resource kinds, grouped
implicitly by API group. As the application evolves toward a Lens IDE-style workspace (ADR-0051),
the navigation surface must handle a substantially broader catalogue. Two new structural concerns
emerge that ADR-0013 does not address:

1. **Sidebar category grouping** — operators navigating 51+ kinds need a categorical tree
   (Workloads, Config, Network, Storage, Access Control, Custom Resources) rather than a flat
   alphabetical list or an API-group list.

2. **Multi-document tab system** — clicking a resource kind node in the sidebar must open a tab in a
   persistent tab bar. Tabs must persist across application launches, survive cluster reconnection,
   and support multiple tabs of the same kind and cross-cluster tabs coexisting simultaneously. The
   former model (one active view per NavigationSplitView selection) is incompatible with this
   requirement.

This ADR defines the canonical resource kind taxonomy (51 standard kinds across 8 categories plus
dynamic CRD grouping), the sidebar category tree structure, and the multi-document tab system
contract including tab identity, persistence, ownership of watch streams, and the `OpenTabsActor`.

## Decision drivers

- **Operator ergonomics** — production clusters surface dozens of resource kinds. Flat lists are
  unusable at scale; categorical grouping with disclosure is the established pattern (Lens, k9s,
  Rancher Dashboard).
- **Tab persistence** — operators who close and reopen the application expect to resume exactly
  where they left off, including which resource kinds were open in which clusters.
- **Watch stream ownership** — ADR-0036 defines watch stream lifecycle but does not assign ownership
  to a UI construct. Tabs are the natural owner: opening a tab starts its watch; closing a tab
  cancels it. Sidebar selection alone cannot own a watch because the sidebar is a read-only
  projection.
- **Cross-cluster coexistence** — the cluster strip (ADR-0051) enables multiple cluster sessions to
  be active simultaneously. Tabs from different clusters must coexist in the tab bar without
  interference.
- **CRD discovery completeness** — ADR-0013 defined the CRD discovery flow but did not specify how
  discovered CRD groups are surfaced in the sidebar tree. CRDs must appear under a dedicated "Custom
  Resources" section, grouped by API group.

## Considered options

- **Option A** — Categorical sidebar tree + multi-document tab bar (chosen).
- **Option B** — Categorical sidebar tree + single active view per cluster (no persistent tabs).
- **Option C** — Flat kind list + single active view (current MVP model, extended to 51 kinds).

## Decision outcome

Chosen option — **Option A**, because:

- Categorical grouping is the proven UX pattern for navigating large kind catalogues.
- Persistent tabs are a hard requirement from the UI refactor goal (Lens IDE parity).
- Option B cannot satisfy the cross-cluster coexistence requirement: with a single view per cluster,
  switching the active cluster discards the previous cluster's open view.
- Option C is a regression for users accustomed to IDE-style navigation.

### Resource kind taxonomy (51 standard kinds)

The taxonomy is organised into 8 named categories that map directly to sidebar section headers. Each
category maps to one or more Kubernetes API groups. All 51 kinds extend the ADR-0013 operation
surface; per-kind operation constraints remain as defined in ADR-0013 and the
`resource_descriptor.cue` schema.

#### Category: Overview

Cluster-scoped summary views. Not Kubernetes resource kinds per se; rendered as synthetic read
models assembled from multiple API calls.

- `ClusterOverview` (synthetic) — cluster health, node summary, namespace count, pod phase
  distribution, event feed.

#### Category: Nodes

- `Node` — cluster-scoped. `core/v1`. Operations: `list`, `get`, `watch`, `edit-yaml`, `events`,
  `logs` (via node log endpoint).

#### Category: Workloads (9 kinds)

- `Deployment` — `apps/v1`.
- `DaemonSet` — `apps/v1`.
- `StatefulSet` — `apps/v1`.
- `ReplicaSet` — `apps/v1`.
- `Pod` — `core/v1`.
- `Job` — `batch/v1`.
- `CronJob` — `batch/v1`.
- `HorizontalPodAutoscaler` — `autoscaling/v2`.
- `VerticalPodAutoscaler` — `autoscaling.k8s.io/v1` (optional; absent if CRD not installed).

Operations per kind follow ADR-0013. `HorizontalPodAutoscaler` adds: `list`, `get`, `watch`,
`edit-yaml`, `delete`, `events`.

#### Category: Config (12 kinds)

- `ConfigMap` — `core/v1`.
- `Secret` — `core/v1`. Value display redacted by default.
- `ServiceAccount` — `core/v1`.
- `PersistentVolumeClaim` — `core/v1`.
- `ResourceQuota` — `core/v1`. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`.
- `LimitRange` — `core/v1`. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`.
- `PodDisruptionBudget` — `policy/v1`. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`.
- `HorizontalPodAutoscaler` — also present in Config for discoverability (alias entry).
- `PriorityClass` — `scheduling.k8s.io/v1`. Cluster-scoped. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`.
- `RuntimeClass` — `node.k8s.io/v1`. Cluster-scoped. Operations: `list`, `get`, `watch`,
  `edit-yaml`.
- `MutatingWebhookConfiguration` — `admissionregistration.k8s.io/v1`. Cluster-scoped. Operations:
  `list`, `get`, `watch`, `edit-yaml`.
- `ValidatingWebhookConfiguration` — `admissionregistration.k8s.io/v1`. Cluster-scoped. Operations:
  `list`, `get`, `watch`, `edit-yaml`.

#### Category: Network (9 kinds)

- `Service` — `core/v1`.
- `Endpoints` — `core/v1`.
- `Ingress` — `networking.k8s.io/v1`.
- `IngressClass` — `networking.k8s.io/v1`. Cluster-scoped. Operations: `list`, `get`, `watch`,
  `edit-yaml`.
- `NetworkPolicy` — `networking.k8s.io/v1`.
- `EndpointSlice` — `discovery.k8s.io/v1`. Operations: `list`, `get`, `watch`, `edit-yaml`.
- `HTTPRoute` — `gateway.networking.k8s.io/v1` (optional; absent if Gateway API not installed).
  Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`.
- `GatewayClass` — `gateway.networking.k8s.io/v1`. Cluster-scoped (optional).
- `Gateway` — `gateway.networking.k8s.io/v1` (optional).

#### Category: Storage (6 kinds)

- `PersistentVolume` — `core/v1`. Cluster-scoped.
- `PersistentVolumeClaim` — `core/v1`. (alias from Config for discoverability).
- `StorageClass` — `storage.k8s.io/v1`. Cluster-scoped.
- `VolumeAttachment` — `storage.k8s.io/v1`. Cluster-scoped. Operations: `list`, `get`, `watch`,
  `edit-yaml`.
- `CSINode` — `storage.k8s.io/v1`. Cluster-scoped. Operations: `list`, `get`, `watch`.
- `CSIDriver` — `storage.k8s.io/v1`. Cluster-scoped. Operations: `list`, `get`, `watch`,
  `edit-yaml`.

#### Category: Namespaces

- `Namespace` — `core/v1`. Cluster-scoped.

#### Category: Access Control (6 kinds)

- `Role` — `rbac.authorization.k8s.io/v1`.
- `RoleBinding` — `rbac.authorization.k8s.io/v1`.
- `ClusterRole` — `rbac.authorization.k8s.io/v1`. Cluster-scoped.
- `ClusterRoleBinding` — `rbac.authorization.k8s.io/v1`. Cluster-scoped.
- `ServiceAccount` — `core/v1`. (alias from Config for discoverability).
- `TokenRequest` — virtual entry. Opens the token request form. Not a list view.

#### Category: Events

- `Event` — `events.k8s.io/v1` and `core/v1` (merged view). Operations: `list`, `get`, `watch`.

#### Category: Custom Resources (dynamic)

CRD instances grouped by API group name. Groups are discovered dynamically as specified in ADR-0013.
Each group becomes a collapsible section in the "Custom Resources" sidebar area. The
`CustomResourceDefinition` meta-kind appears as a top-level entry ("CRD Catalog") at the top of the
Custom Resources section.

The total catalogue count is 51 named standard kinds (counting canonical entries, not alias
duplicates). Alias entries in secondary categories share the same `ResourceKindDescriptor` and do
not create duplicate watch streams.

### Multi-document tab system contract

#### Tab identity

A `DocumentTab` is uniquely identified by the tuple
`(clusterId, tabKind, namespace?, kindName?, resourceName?)`. The `tabKind` enum is:

- `resourceList` — a list view for a specific Kubernetes kind and namespace.
- `resourceDetail` — a detail view for a specific named resource.
- `clusterOverview` — the synthetic ClusterOverview for a cluster.
- `helmReleases` — the Helm release list for a cluster.
- `helmDetail` — detail for a specific Helm release.
- `events` — the events feed for a cluster or namespace.
- `terminalSession` — a terminal session (Pod exec or Node debug).

Each tab carries: `tabId` (UUIDv7), `clusterId`, `tabKind`, contextual identifiers (namespace, kind,
name), `openedAt` (RFC 3339), `isPinned` (bool), and `scrollPosition` (optional opaque blob).

#### Tab ownership of watch streams

Tabs are the authoritative owners of Kubernetes watch streams. The invariant is:

- Opening a tab (any `resourceList` or `resourceDetail` tab) starts a watch stream for the
  corresponding kind+namespace via `WatchPort` on the cluster's `ClusterSessionActor`.
- Closing a tab cancels the watch stream Task associated with that tab. The cancellation propagates
  through Swift structured concurrency to the `WatchPort` adapter.
- A sidebar tree selection that does not open a new tab MUST NOT start a watch stream.
- If a tab is already open for the selected (clusterId, tabKind, namespace, kindName), clicking the
  sidebar node brings the existing tab to focus rather than opening a duplicate.

#### OpenTabsActor

All tab state mutations are isolated to `OpenTabsActor`, a Swift `actor`. The actor:

- Maintains the ordered list of open `DocumentTab` values for all clusters.
- Exposes an `AsyncStream<[DocumentTab]>` for the tab bar view model.
- Handles `openTab`, `closeTab`, `focusTab`, `reorderTab`, `pinTab`, `unpinTab` commands.
- On `closeTab`, cancels the associated watch Task (if any) by cancelling the `Task` stored in the
  tab's watcher registry.
- Persists the tab list to the filesystem on every mutation (debounced 500 ms) to the path defined
  in ADR-0026 addendum.
- On cold launch, restores persisted tabs. For `resourceList` tabs, restores immediately. For
  `resourceDetail` tabs, restores only if the cluster session is available.

The sidebar tree is a read-only SwiftUI projection of `OpenTabsActor` state and
`ClusterSessionActor` state. It does not mutate tabs directly; it issues commands to
`OpenTabsActor`.

#### Tab bar layout

The tab bar occupies the top of the content area (below the window toolbar, above the resource
list/detail pane). Layout conventions:

- Tabs are horizontally scrollable when total width exceeds the available frame.
- Each tab chip shows: cluster avatar (initials, color from cluster strip), kind icon (SF Symbol),
  context label (kind name + namespace abbreviation), close button (appears on hover).
- Pinned tabs show a filled pin icon; they cannot be closed via the close button (must be unpinned
  first).
- Dragging a tab chip reorders it within the tab bar. Reorder is persisted immediately.
- The active tab is highlighted with the `accentBrand` token underline.
- Maximum visible tabs before scroll: unbounded (operator-controlled via horizontal scroll).
- Maximum persisted tabs per cluster: 20. Opening a 21st tab closes the oldest non-pinned tab
  automatically with a toast notification.

#### Tab persistence path

Tab state is persisted to:

```
~/Library/Application Support/K8sManager/clusters/<clusterId>/open-tabs.json
```

The JSON schema is defined in `contexts/app_shell/schemas/open_tabs_state.cue`.

> **Addendum — Onda 3 implementation note (2026-05-16).** The first production wiring of
> `OpenTabsActor` (commit landing alongside ADR-0053) persists a SINGLE process-wide tab list at
> `~/Library/Application Support/K8sManager/workspace/open-tabs.json` rather than per-cluster. The
> shared port is registered once at the composition root and routes every `openTab(_:)` call to the
> same actor instance, regardless of `DocumentTab.clusterId`.
>
> This deviates from the per-cluster contract above. It is accepted as a transitional state because
> the single-active-cluster session model (ADR-0025) currently guarantees only one cluster is
> being inspected at a time, so cross-cluster tab corruption cannot occur at runtime. The deviation
> will be closed in the next onda by:
>
> 1. Introducing a `OpenTabsRegistry` actor that lazily creates one `OpenTabsActor` per `ClusterId`
>    with the canonical per-cluster persistence path.
> 2. Routing `openTab(_:)` through the registry based on `DocumentTab.clusterId`.
> 3. Updating the canvas tab bar to scope its visible tabs to the active cluster's actor instance.
>
> Until that work lands, restoring tabs after a cluster switch will surface the union of tabs from
> all clusters in the single file. A code TODO marks the deviation at the registration site in
> `K8sManagerApp.swift`.

### Consequences

Positive:

- The categorical sidebar tree is self-documenting: operators discover available kinds without
  reading documentation.
- Tab ownership of watch streams provides a clear lifecycle boundary: no orphaned watches.
- Persistent tabs restore operator workflow across application restarts.
- Cross-cluster tabs coexist without interference because tab identity includes `clusterId`.

Negative:

- `OpenTabsActor` is a new global actor with shared mutable state; its watch-task registry must be
  carefully managed to avoid Task leaks.
- The 20-tab-per-cluster limit is a heuristic; operators with complex workflows may find it
  restrictive. The limit is configurable via `app_shell/theme_preference` (future).
- Alias entries (kinds that appear in multiple categories) require the UI to de-duplicate watch
  streams by tab identity, not by sidebar position.

## Pros and cons of the options

### Option A — Categorical tree + multi-document tab bar (chosen)

- Good, because categorical grouping reduces cognitive load for operators navigating 51 kinds.
- Good, because tabs provide persistent, named anchors for operator workflows.
- Good, because tab ownership of watches provides a single canonical lifecycle contract.
- Bad, because the `OpenTabsActor` adds implementation complexity beyond the current MVP state
  model.

### Option B — Categorical tree + single view per cluster

- Good, because it preserves the existing single-view-per-cluster model with minimal refactoring.
- Bad, because it cannot support cross-cluster coexistence or tab persistence across launches.
- Bad, because closing and reopening the application discards all navigation state.

### Option C — Flat list + single view (current model extended)

- Good, because zero new UI structure is introduced.
- Bad, because 51 kinds in a flat list is unusable in practice.
- Bad, because it defers the tab and cross-cluster requirements without resolving them.

## Confirmation

- `contexts/app_shell/schemas/open_tabs_state.cue` defines `#DocumentTab` and `#OpenTabsState` and
  is validated in CI via `cue:vet`.
- `contexts/app_shell/schemas/resource_kind_catalog.cue` defines `#ResourceKindCatalog` and
  `#SidebarCategory` and is validated in CI.
- Rego policy `contexts/app_shell/policies/tab_navigation_policy.rego` enforces tab invariants
  (max-per-cluster, isolation, no cross-cluster mutation).
- Gherkin features under `contexts/app_shell/features/` cover: tab open from tree, tab close cancels
  watches, tab persist and restore, resource kind catalog CRD discovery, detail drawer toolbar
  actions.
- `OpenTabsActor` unit tests verify that closing a tab cancels the associated watch Task and removes
  it from the watcher registry.
- An integration test restores 5 persisted tabs for a cluster after a simulated cold launch and
  asserts that each `resourceList` tab re-establishes its watch stream.

## More information

- ADR-0013 — Resource browser scope; original 23-kind catalogue and discovery flow extended here.
- ADR-0021 — App shell design system; window structure refined in ADR-0051.
- ADR-0025 — Per-cluster isolation; `ClusterSessionActor` is the owner of cluster-scoped resources.
- ADR-0026 — State persistence; tab persistence path added in ADR-0026 addendum.
- ADR-0034 — State-driven UI; `OpenTabsActor` feeds `AsyncStream` to tab bar view model.
- ADR-0036 — Watch stream lifecycle; tab-owned watches follow the same state machine.
- ADR-0051 — Multi-cluster workspace; cluster strip and provider grouping in the sidebar.
- ADR-0052 — Custom resource discovery; CRD group rendering in the Custom Resources sidebar section.

## Amendments

### Amendment 1 — Row-tap routing restricted; detail viewing routes to Inspector (2026-05-16)

The rule "clicking a resource kind node in the sidebar must open a tab" (§Multi-document tab system
contract, §Tab identity `resourceDetail`) is narrowed by ADR-0073 (Inspector trailing column).

Row-tap → `openTabs.openTab(.resourceDetail(...))` is now restricted to resource kinds that do NOT
have a registered `ResourceInspectorContent` conformance, plus the explicit "Open in Tab"
context-menu action. For inspector-capable kinds, a row tap updates
`ResourceInspectorViewModel.selectedKey`; no tab is opened.

The `DocumentTab.resourceDetail` case is retained in the `TabKind` enum and in `OpenTabsActor`
for the explicit "Open in Tab" path, for kinds without inspector content, and for persistence
compatibility. The `terminalSession`, `helmDetail`, `clusterOverview`, `events`, and `helmReleases`
tab kinds are unaffected.

Forward reference: ADR-0073 (Inspector trailing column substitutes resource detail tabs).
