# ADR-0071 — Skeleton mandate for resource list view loading states

- Status — Accepted (ratified 2026-05-16)
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none)
- Informed — (none)
- Refines — ADR-0031 (loading states and async resource UX)
- Tags — loading-states, skeleton, ux, resource-list, app-shell

## Context and problem statement

ADR-0031 introduced `AsyncResource<T>` and the skeleton / shimmer / spinner /
progressBar vocabulary for async UI states. The §"Skeleton loaders" section of that
ADR established skeleton as the mandatory loading presentation for "content list —
resource list (pods, deployments, services, etc.)".

During Onda 3 review of screen recordings (frames 17–25 of the 2026-05-16
recording), all resource list views outside the eight workload list views reverted to
a centered `ProgressView()` with "Loading X..." caption text for their initial load
state. Affected views include:

- `ApplicationsView` (cluster-scoped, all namespaces)
- `SecretsListView`, `ConfigMapsListView`, `ResourceQuotasListView`
- `HPAListView`, `VPAListView`, `PodDisruptionBudgetListView`
- Every Config, Network, RBAC, Storage, and Cluster resource list view under
  `Sources/AppShell/Views/Resources/**`

The `ApplicationsView` had a `private var loadingView: some View { WorkloadListSkeleton() }`
computed property already wired correctly, confirming the skeleton implementation exists
and is working — its siblings simply were not adopting it.

This inconsistency violates the operator-trust and "consistent language" requirements
from ADR-0031 §"Decision drivers". An operator navigating from Pods (skeleton loading)
to Secrets (centered spinner) perceives two different application behaviours for the
same fundamental operation.

The root cause is that ADR-0031's spinner permission — "operations expected to complete
in <500 ms" — was applied to all Kubernetes API list calls, even though no list call
can have a bounded latency estimate before the first byte arrives from the cluster.

## Decision drivers

- **Visual consistency** — every resource list view must exhibit the same loading
  presentation so the operator's mental model is stable across all 51 sidebar
  resource kinds.
- **ADR-0031 §"Skeleton loaders" intent** — content list was always in scope for
  skeleton; this ADR clarifies that all resource list surfaces, not only workload
  list surfaces, are content lists under ADR-0031's definition.
- **SwiftUI transition correctness** — the `AsyncResource.loading → .loaded`
  `.transition(.opacity)` animation applied by `ResourceListContainer` works correctly
  only when the `loading` arm renders `SkeletonRow`-based content of the same geometry
  as the final list. Replacing `SkeletonRow` with a centered `ProgressView` shifts
  layout geometry between states and produces a visible layout jump.
- **Operator predictability** — first-load and refresh-triggered load must look the
  same; the operator must not learn two different loading idioms for the same panel
  type.

## Considered options

### Option A — Mandate `SkeletonRow` for all resource list views; ban `ProgressView` in initial list load paths (chosen)

Every view that switches on `AsyncResource<T>` for a Kubernetes API list call renders
`WorkloadListSkeleton(rowCount: 8)` (or an equivalent layout-matched skeleton) in its
`.idle` and `.loading` arms.

- Good, because visual consistency is achieved across all 51 resource kinds.
- Good, because `ResourceListContainer`'s transition animations work without geometry
  jumps.
- Good, because no new component is needed — `WorkloadListSkeleton` already exists
  and is used correctly by the eight workload list views.
- Bad, because a few resource list views with highly distinctive row heights (e.g. node
  list with multi-line condition chips) may require a custom skeleton variant rather
  than reusing `WorkloadListSkeleton` verbatim.

### Option B — Keep both; let each view author choose the loading style

Each resource list view independently decides whether to use skeleton or spinner.

- Good, because no change is required to existing views.
- Bad, because the inconsistency that motivated this ADR is never resolved; new views
  will continue to default to the simpler centered-spinner pattern.
- Bad, because the operator's mental model never stabilises — the same "loading" signal
  manifests differently across the sidebar tree.

### Option C — Replace `SkeletonRow` with `ProgressView` everywhere; degrade workloads to match Config

Standardise on centered `ProgressView` across all resource list views.

- Good, because consistency is achieved.
- Bad, because it degrades the existing workload list views, which already have correct
  skeleton behaviour.
- Bad, because `ResourceListContainer` transition animations regress for all views.
- Bad, because it regresses the operator-trust properties that ADR-0031 §"Operator
  trust" requires.

## Decision outcome

Chosen option — **Option A**.

The motivating evidence is frames 17–25 of the 2026-05-16 recording: `ApplicationsView`
displayed a spinner for six or more seconds with no structural placeholder, while the
adjacent Pods tab showed correctly structured skeleton rows for a comparable first-load
duration.

### Invariant (binding)

> **No `ProgressView` for initial resource list load. Every list view that fetches
> via `KubernetesResourceListPort` (or any equivalent domain port returning a
> Kubernetes API list call) MUST render `WorkloadListSkeleton(rowCount: N)` — or a
> layout-matched skeleton variant — for its `.idle` and `.loading` states.**

Specifically:

- Any view that switches on `AsyncResource<T>` and presents content from a Kubernetes
  API list call MUST render `WorkloadListSkeleton(rowCount: 8)` (or equivalent) for
  the `.idle` and `.loading` arms.
- Centered `ProgressView()` with "Loading X..." caption is prohibited for these arms.
- The 200 ms transition throttle defined in ADR-0031 §"200 ms transition throttle"
  remains in force — sub-200 ms loads skip the skeleton entirely; the skeleton is
  shown only when the operation exceeds the throttle threshold.
- The spinner exception from ADR-0031 for "quick ops" (<500 ms) applies only to
  non-list surfaces: namespace switch confirmation, kubeconfig parse, search index
  warm-up. It does NOT apply to any `KubernetesResourceListPort.list(...)` call.

### Permitted `ProgressView` usage

`ProgressView` remains permitted for:

- The `refreshButton` spinner inside `GlobalNamespacePill` (namespace list refresh).
- Inline row-level spinners for mutating operations (delete, apply, rollback) that
  target a single resource, not a list.
- The `ResourceListContainer` toolbar slot during list refresh (not initial load).
- Full-screen bootstrap states during cluster connect (`ClusterConnectView`).

### Affected surfaces

All resource list views in `Sources/AppShell/Views/Resources/**` and
`Sources/AppShell/Views/Applications/ApplicationsView.swift`. The
`ApplicationsView` already uses `WorkloadListSkeleton()` via its `loadingView`
private computed property; this ADR confirms it as the mandatory pattern for all
sibling views.

### Implementation pattern

```swift
// ResourceListContainer.swift — .loading arm (canonical)
case .loading:
    WorkloadListSkeleton(rowCount: 8)
        .transition(.opacity)

// Custom variant for views with non-standard row heights
case .loading:
    WorkloadListSkeleton(rowCount: 6)   // smaller for tall-row views
        .transition(.opacity)
```

Views that require a skeleton whose row geometry differs significantly from
`SkeletonRow`'s default height (44 pt) should define a local `skeleton` computed
property returning the appropriate `WorkloadListSkeleton` call, mirroring the pattern
established by `ApplicationsView.loadingView`.

## Pros and cons of the options

### Option A (chosen)

- Pro — visual consistency across all 51 resource kinds; zero new components required.
- Pro — transition animations in `ResourceListContainer` remain geometry-stable.
- Pro — new views added in future ondas inherit the correct default by convention.
- Con — custom skeleton variants needed for views with non-standard row heights.

### Option B

- Pro — no immediate change required to existing views.
- Con — inconsistency persists; new views default to spinner; operator trust regresses.

### Option C

- Pro — consistency achieved.
- Con — degrades existing workload list views and all transition animations.
- Con — violates ADR-0031 §"Operator trust" requirement.

## Confirmation

- `Sources/AppShell/Views/Resources/**/*ListView.swift` — each file must instantiate
  `WorkloadListSkeleton` (or a layout-matched variant) in its `.loading` (and `.idle`
  if applicable) arm. There is no compile-time mechanism to enforce this; a SwiftLint
  custom rule is tracked as future work.
- `Sources/AppShell/Views/Applications/ApplicationsView.swift` — `loadingView` private
  computed property returns `WorkloadListSkeleton()`. This file already conforms and
  serves as the reference implementation for sibling views.

## More information

- ADR-0031 — Loading states and async resource UX; defines `AsyncResource<T>`,
  `WorkloadListSkeleton`, `ShimmerModifier`, and the 200 ms throttle. ADR-0071 extends
  the skeleton vocabulary established there to all non-workload resource list views.
- ADR-0034 — State-driven realtime UI architecture; `AsyncResource` is a primary state
  type in `@Observable` view models.
- ADR-0021 — App shell design system and layout; design tokens that govern skeleton
  row height, spacing, and corner radius used by `SkeletonRow`.
