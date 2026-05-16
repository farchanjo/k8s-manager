# ADR-0067 — Applications cluster scope (Helm releases plus GitOps applications)

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0015 (Helm native phased implementation), ADR-0050 (resource navigation taxonomy),
  ADR-0051 (multi-cluster workspace)
- Tags — applications, helm, argocd, flux, gitops, resource-browser, sidebar-taxonomy

## Context and problem statement

The feature-gap analysis against the Lens × Mirantis Prism AI reference recording (see
`docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`, item R16-a) identifies that
Lens presents an "Applications" entry under each cluster in the sidebar tree. In the reference
recording this entry sits between "Overview" and "Nodes" in the per-cluster tree hierarchy, at the
same disclosure level as Workloads, Config, Network, and Storage.

In Lens the Applications view aggregates three distinct source kinds under a single higher-order
navigation entry:

- Helm releases — decoded from `helm.sh/release.v1` Secrets (same source as ADR-0015 Phase 1).
- ArgoCD `Application` and `ApplicationSet` custom resources (`argoproj.io/v1alpha1`).
- Flux `Kustomization` custom resources (`kustomize.toolkit.fluxcd.io/v1`).

K8S-Manager already surfaces Helm under a dedicated "Helm" subtree in the sidebar tree (ADR-0051
sidebar tree specification). That subtree provides the Helm catalogue, repository browser,
release list, and release detail views as defined in ADR-0015. Operators who use GitOps tooling
(ArgoCD or Flux) today see those custom resources only under "Custom Resources → argoproj.io" or
"Custom Resources → kustomize.toolkit.fluxcd.io", which requires knowing the CRD group name in
advance and offers no higher-order lifecycle view.

The question this ADR answers is: should K8S-Manager introduce a dedicated "Applications" root in
the per-cluster sidebar tree, distinct from the existing "Helm" subtree, and if so, what should it
aggregate in v1?

## Decision drivers

- **Operator mental model** — applications are a higher-order concept than raw Kubernetes kinds.
  An operator who deployed workloads via Helm, ArgoCD, or Flux thinks in terms of named
  application releases, not in terms of Secrets or custom resource API groups. Surfacing all of
  these under a single "Applications" entry matches the mental model without forcing the operator
  to know implementation details.
- **GitOps coverage is increasingly the norm** — production clusters observed in the reference
  recording carry ArgoCD CRDs (`argoproj.io`, `app.kubernetes.io/managed-by=argocd` labels). A
  growing proportion of operators manage workloads exclusively via GitOps; the sidebar tree
  should not bury their primary management surface under the Custom Resources catch-all.
- **Phase discipline from ADR-0015** — ADR-0015 establishes a phased model for Helm. The same
  principle applies here: deliver a scoped v1 rather than attempting to cover all GitOps tools
  simultaneously. Pulling in ArgoCD and Flux CRD support expands the surface area significantly
  and introduces CRD discovery dependencies (ADR-0052) that need additional integration work.
- **Avoiding duplication with the existing Helm subtree** — the "Helm" sidebar entry defined in
  ADR-0051 provides the full Helm catalogue (repositories, chart browser, release management).
  An "Applications" view that also exposes all Helm releases would create two visible entry
  points for the same data. The Applications view must be positioned as a higher-level summary,
  not a replacement.
- **CRD discovery prerequisite for GitOps** — surfacing ArgoCD `Application` or Flux
  `Kustomization` resources requires confirming CRD installation via ADR-0052 discovery. In
  clusters that do not have ArgoCD or Flux installed the section must be entirely absent, not
  empty. Implementing the conditional visibility logic for both tools in v1 is unnecessary scope.

## Considered options

### Option A — Keep Helm separate, no Applications root

Maintain the current sidebar structure where Helm releases appear under the "Helm" subtree only.
GitOps custom resources remain under "Custom Resources → [API group]". No new top-level entry is
added.

### Option B — Introduce Applications root aggregating Helm releases, ArgoCD, and Flux

Add an "Applications" root to the per-cluster sidebar tree that aggregates Helm releases decoded
from Secrets, ArgoCD `Application` and `ApplicationSet` resources, and Flux `Kustomization`
resources. The view discovers which tools are installed via CRD presence (ADR-0052) and
conditionally surfaces each section. If none are installed, the Applications entry is hidden.

### Option C — Applications root for Helm only, defer GitOps coverage (chosen)

Add an "Applications" root that reads from the same `HelmManagement` actor read model as the
existing Helm subtree. Surface a flat, namespace-filtered list of Helm releases with columns: Name,
Chart, Version, Status, Updated, Namespace, Revision. Reserve the sub-sections for ArgoCD and Flux
as deferred extension hooks, each gated behind CRD discovery (ADR-0052). When no Helm releases are
present, display a targeted empty state. The existing "Helm" subtree is preserved as the
full-management surface (repositories, catalogue, detail, rollback).

## Decision outcome

Chosen option — **Option C**, because:

- It delivers the operator-facing "Applications" summary immediately without requiring the CRD
  discovery integration work for ArgoCD and Flux.
- The `HelmManagement` read model (ADR-0015 Phase 1) is already available; the Applications view
  is a filtered projection of existing data, not a new data pipeline.
- The existing "Helm" subtree is preserved intact, so operators who rely on its catalogue and
  repository browser are not disrupted.
- The deferred extension contract (described below) provides a clear path to add GitOps coverage
  in follow-up ADRs without revisiting this decision.

### Sidebar tree placement

The "Applications" entry is inserted under each cluster node in the per-cluster sidebar tree,
between "Overview" and "Nodes":

```
[Provider section header]
  [Cluster display name]
    Overview
    Applications          ← new in ADR-0067
    Nodes
    Workloads
    Config
    Network
    Storage
    Namespaces
    Events
    Helm
    Access Control
    Custom Resources
```

The "Applications" entry is a single disclosure-less leaf node in the sidebar tree (it does not
expand to sub-kinds). Clicking it opens a `DocumentTab` with `tabKind = applicationsList`
(a new tab kind added to the `DocumentTab` enum from ADR-0050).

### ApplicationsView data source

`ApplicationsView` reads from the `HelmManagement` actor's read model (the same source used by the
Helm release list view). It applies the active global namespace filter (ADR-0053). The view presents
a column-sortable list with the following columns:

- **Name** — the Helm release name.
- **Chart** — the chart name, without the repository prefix (e.g. `nginx-ingress`, not
  `ingress-nginx/nginx-ingress`).
- **Version** — the chart version string (e.g. `4.10.0`).
- **Status** — the Helm status enum value rendered as a status chip:
  `deployed` (green), `failed` (red), `pending-install`, `pending-upgrade`, `pending-rollback`
  (amber), `uninstalled` (grey), `superseded` (grey, hidden by default).
- **Updated** — the `info.last_deployed` timestamp formatted as a relative duration
  (e.g. "3 days ago").
- **Namespace** — the release namespace.
- **Revision** — the current revision integer.

Default sort order: by Name, ascending. The operator may click any column header to re-sort.

Superseded revisions are excluded from the list by default (matching the Helm subtree behaviour
from ADR-0015).

### Empty state

When no Helm releases are present in the active namespace (or in any namespace if the global filter
is set to "All Namespaces"), the `ApplicationsView` displays a centred empty state with:

- Heading: "No Helm releases in this cluster"
- Body: "Try `helm install` or import a release via the Helm tab."
- A single secondary action button labelled "Go to Helm" that brings the "Helm" sidebar subtree
  into focus.

### Row action: navigate to Helm release detail

Clicking a row in `ApplicationsView` opens the Helm release detail view in the standalone Helm
subtree. It does NOT open a separate Applications-scoped detail view. The release detail view is
the single source of truth for release history, rollback, values, and manifest inspection, as
defined in ADR-0015.

The navigation is implemented by issuing an `openTab(_:)` command to `OpenTabsActor` with
`tabKind = helmDetail` and the release identity, reusing the existing tab kind.

### Deferred extension contract for GitOps tools

When ArgoCD CRDs (`applications.argoproj.io`, `applicationsets.argoproj.io`) are discovered via
ADR-0052, a follow-up ADR (designated ADR-N below, see Followups) may introduce a sibling section
under "Applications" that lists ArgoCD `Application` resources. This section is NOT built in v1.
The CUE schema for `#ApplicationsViewState` reserves an `argocdEnabled: bool` field (default
false) to support this extension without a schema-breaking change.

Similarly, when Flux CRDs (`kustomizations.kustomize.toolkit.fluxcd.io`) are discovered, a
follow-up ADR (ADR-N+1) may introduce a Flux Kustomizations sub-section. The CUE schema also
reserves a `fluxEnabled: bool` field (default false).

No code that reads ArgoCD or Flux CRDs is introduced in this ADR.

### Cross-link to existing Helm subtree

The standalone "Helm" subtree defined in ADR-0051 (sidebar position between "Events" and
"Access Control") is not removed or replaced by this ADR. Its responsibilities remain:

- Helm repository browser (list, add, remove repositories).
- Chart catalogue (search, browse charts from configured repositories).
- Full release list with history, values, manifest diff, and rollback.
- Phase 2 install and upgrade flows (ADR-0015 Phase 2 roadmap).

"Applications" is intentionally positioned as a higher-level summary view for operators who want
a quick inventory of what is deployed. "Helm" remains the management surface for operators who
need to perform operations on releases.

## Pros and cons of the options

### Option A — Keep Helm separate, no Applications root

- Good, because no new sidebar entry or view model is needed.
- Bad, because the sidebar tree deviates from the Lens reference UX in a way that is immediately
  noticeable to operators migrating from Lens.
- Bad, because GitOps operators have no higher-order surface and must navigate to Custom Resources
  to find their application resources.

### Option B — Introduce Applications root aggregating Helm, ArgoCD, and Flux

- Good, because the view matches the full Lens Applications scope.
- Bad, because implementing conditional visibility for ArgoCD and Flux requires CRD discovery
  integration (ADR-0052) and the Rego policy for CRD-gated sidebar entries — significant scope.
- Bad, because clusters without any of the three tools would still show the Applications entry
  (unless a conditional-hide rule is introduced), adding noise to the sidebar.
- Bad, because delivering all three aggregation sources together is not aligned with the phased
  delivery model established in ADR-0015.

### Option C — Applications root for Helm only, defer GitOps coverage (chosen)

- Good, because it satisfies the R16-a gap (Applications entry visible per cluster) immediately.
- Good, because the data source is already available from ADR-0015 Phase 1 with no new adapter
  work.
- Good, because the deferred extension contract is explicit and does not block the feature from
  shipping.
- Bad, because GitOps-only operators see an empty Applications view until ADR-N and ADR-N+1
  land.

## Confirmation

- `contexts/resource_browser/schemas/applications_view_state.cue` defines `#ApplicationsViewState`
  (including reserved `argocdEnabled` and `fluxEnabled` fields) and is validated in CI via
  `cue:vet`.
- Rego policy `contexts/resource_browser/policies/applications_view_policy.rego` enforces that
  `ApplicationsView` reads exclusively from the `HelmManagement` read model and does not query
  ArgoCD or Flux CRD endpoints until the corresponding `*Enabled` flag is set.
- Gherkin feature `contexts/resource_browser/features/applications-scope.feature` covers the five
  scenarios defined at ADR write time: Applications entry visible per cluster, empty state when
  no Helm releases, column list contract, namespace filter, and row action navigates to Helm
  detail.
- `workspace.dsl` registers `ApplicationsView` as a component of the `resource_browser` container
  with a dependency on `HelmManagement` read model.
- `OpenTabsActor` unit tests verify that opening an `applicationsList` tab correctly stores and
  restores the tab across cold launches.

## Followups

- **ADR-N — ArgoCD Applications scope** — once the ArgoCD CRD group (`argoproj.io`) is confirmed
  as discoverable via ADR-0052, define the ArgoCD `Application` and `ApplicationSet` sub-section
  under the Applications sidebar entry. Define sync-status chips, health status mapping, and the
  link to the raw custom resource view in "Custom Resources".
- **ADR-N+1 — Flux Kustomizations scope** — once the Flux CRD group
  (`kustomize.toolkit.fluxcd.io`) is confirmed as discoverable via ADR-0052, define the Flux
  `Kustomization` sub-section under the Applications sidebar entry. Define readiness-status chips
  and the link to the raw custom resource view.

## More information

- ADR-0015 — Helm native phased implementation; defines the `HelmManagement` actor and the
  `helm.sh/release.v1` Secret decoding pipeline that `ApplicationsView` reads from.
- ADR-0050 — Resource navigation taxonomy; defines the `DocumentTab` identity contract and the
  `OpenTabsActor` that `ApplicationsView` uses for tab navigation.
- ADR-0051 — Multi-cluster workspace; defines the per-cluster sidebar tree structure that this
  ADR extends with the "Applications" entry.
- ADR-0052 — Custom resource discovery; defines the CRD discovery pipeline that the deferred
  ArgoCD and Flux extension hooks will depend on.
- ADR-0053 — Global namespace filter; defines the namespace propagation mechanism that
  `ApplicationsView` respects.
- Feature-gap analysis — `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`,
  item R16-a.
