# Bounded Context — `context_navigation`

## Purpose

Own the model of "which Kubernetes context is the operator looking
at right now, which have they used recently, and which have they
pinned". This context owns navigation state. It does not own
clusters, credentials, or health probes.

## Ubiquitous language

- **Active context** — the single `ContextId` the operator is
  currently focused on. At most one is active per application run.
- **Recents window** — a bounded most-recently-used list of
  contexts. Capped at 32 entries; pinned entries are exempt from
  pruning.
- **Pinned context** — an operator-chosen entry that appears in a
  dedicated section of the sidebar, persists across launches, and
  is not pruned from recents.
- **Selection event** — the moment the operator picks a different
  context. Emits `ActiveContextChanged`.
- **Fallback** — automatic re-selection of the kubeconfig-level
  current-context when the previously active context disappears
  from the kubeconfig.

## Tactical roles

- **`ActiveContext`** — AggregateRoot. Singleton per application
  run. Holds `contextId`, `selectedAtRFC3339`, `selectedBy`.
- **`RecentContextWindow`** — ReadModel. Materialised from
  `UserDefaults`; not the authoritative store for any invariant
  beyond ordering and counts.
- **`RecentContextEntry`** — ValueObject inside the window.
- **`PinnedContext`** — ValueObject. Persisted in `UserDefaults`
  keyed by `ContextId`. Survives application restarts.
- **`ContextSwitcher`** — DomainService. Pure function
  `(currentActive, newContextId, clock) -> ActiveContext`. Emits a
  domain event when the active context actually changes.
- **`RecentsWindowUpdater`** — DomainService. Pure function
  `(window, selectedContextId, clock) -> window`. Caps at 32, never
  prunes a pinned entry.
- **`ContextRepositoryPort`** — Port. Persists pins and recents
  metadata. Default adapter wraps `UserDefaults`.

## Dependencies

- Consumes `ClusterReadModel` from `cluster_connectivity` to
  display human-friendly names alongside `ContextId` values.
- Depends on the shared kernel for `ContextId`, `ClusterId`.
- Does not import `Yams`, `SwiftkubeClient`, or any networking
  library. Pure navigation logic plus a `UserDefaults` adapter.

## Read models exposed to other contexts

- `ActiveContextReadModel` — what to render in the title bar and
  the menu bar. Consumed by `app_shell`.
- `SidebarReadModel` — combined view of pinned + recents. Consumed
  by `app_shell`.

## Invariants

- At most one `ActiveContext` exists per application run.
- A pinned `ContextId` SHALL not be pruned from the recents window
  while it is pinned.
- The recents window MUST not exceed `maxEntries` (default 32)
  non-pinned entries.
- A selection that targets the currently active context is a no-op
  and emits no event.
- If the kubeconfig reload removes the active context, the next
  `ActiveContext` emitted has `selectedBy="fallback"` and the
  operator is shown a non-blocking banner.

## Out of scope

- Cluster health, parsing, or credentials. See `cluster_connectivity`.
- UI rendering and animation. See `app_shell`.
- Multi-window navigation. The MVP runs one main window only.
