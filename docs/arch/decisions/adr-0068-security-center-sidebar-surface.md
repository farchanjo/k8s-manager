# ADR-0068 — Security Center sidebar surface and content

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none)
- Informed — (none)
- Refines — ADR-0049 (app shell policy coverage), ADR-0050 (resource navigation taxonomy),
  ADR-0051 (multi-cluster workspace)
- Tags — security-center, sidebar, resource-browser, app-shell, policy-coverage

## Context and problem statement

The feature gap analysis recorded on 2026-05-16 (`feature-gap-analysis-lens-prism-ai.md`,
item R16-b) identified that Lens surfaces a Security Center entry in every cluster's sidebar
tree, placed after the Custom Resources section. K8S-Manager already contains four SwiftUI
views that constitute the Security Center:

- `SecurityOverviewView` — cluster-wide security posture summary.
- `SecurityImagesView` — per-image inventory with digest and pull-secret bindings.
- `SecurityResourcesView` — per-namespace inventory of resources that breach security baselines.
- `SecurityRolesView` — per-role inventory of RBAC permissions sorted by privilege level.

These views exist in `project/Sources/AppShell/Views/` but are not anchored in the sidebar
taxonomy defined by ADR-0050. ADR-0050 enumerates 51 standard kinds across 8 categories and
one dynamic Custom Resources section; it does not declare a Security Center category.
Similarly, `SidebarTreeViewModel` has no tree node for Security Center, so operators cannot
reach these views through normal navigation.

No external vulnerability scanner integration (Kubescape, Trivy, Falco) has been decided or
implemented. Security Center v1 therefore operates exclusively on data read from the
in-cluster Kubernetes API. Scanner integration is deferred to a follow-up ADR.

This ADR declares the sidebar entry point, specifies the placement and order of sub-entries,
contracts each sub-entry's data model, defines empty states, and cross-references ADR-0049
policy coverage requirements.

## Decision drivers

- **Operator security audit workflow** — operators performing routine security reviews need a
  single canonical sidebar entry that groups all security posture views. Scattered placement
  across Workloads, Access Control, and Config categories would require navigating multiple
  sections for a single audit task.
- **Single canonical entry point** — the four security views already exist as implementations;
  this ADR provides the navigation contract that makes them discoverable and reachable without
  deep knowledge of the view hierarchy.
- **No external scanner dependency in v1** — the Security Center must deliver value immediately
  from data already available through the Kubernetes API (`PodSpec`, RBAC resources,
  `NetworkPolicy`, admission label annotations). Scanner integration requires separate
  authentication, rate-limit, and data-model decisions that belong in a follow-up ADR.
- **Placement coherence with ADR-0050 taxonomy** — the new section must integrate into the
  existing categorical tree without breaking the 51-kind taxonomy or the CRD discovery
  subsection already defined by ADR-0050 and ADR-0052.
- **ADR-0049 policy coverage** — new navigation surface in `app_shell` must be auditable by the
  Rego policy set established in ADR-0049, or must document why no new policy invariants apply.

## Considered options

### Option A — Security Center as a top-level cluster section with four sub-entries

A new expandable top-level section labelled "Security Center" is added after the Custom
Resources section in the per-cluster sidebar tree. The section contains exactly four sub-entries
in fixed order: Overview, Images, Resources, Roles.

### Option B — Security Center as a single dashboard view with internal tabs

A single sidebar leaf entry labelled "Security Center" opens a composite view with four
internal tabs (Overview, Images, Resources, Roles). Navigation within the section uses the
tab bar already defined in ADR-0050 rather than the sidebar tree.

### Option C — Scattered entries per kind family

Security-related views are distributed across their nearest kind families: Images under
Workloads, Resources under Workloads or Config, Roles under Access Control. No discrete
Security Center section exists.

## Decision outcome

**Chosen option: A — Security Center as a top-level cluster section with four sub-entries.**

Rationale:

- Option A mirrors the reference implementation (Lens) and meets the single-canonical-entry
  requirement. Operators can expand or collapse the entire section in one interaction.
- Option B pushes navigation into tab state managed by `OpenTabsActor`. Because the Security
  Center views are composite read models (not Kubernetes kind list views), they do not map
  cleanly to the `DocumentTab` identity tuple `(clusterId, tabKind, namespace?, kindName?)`.
  Forcing them into a tab kind adds a new `tabKind` variant (`securityCenter`) while gaining
  nothing over a sidebar sub-tree.
- Option C fails the single-canonical-entry requirement and forces operators to cross section
  boundaries for a unified security audit.

### Sidebar taxonomy placement

The Security Center section is inserted into the per-cluster sidebar tree defined in ADR-0051
after the Custom Resources section and before the cluster footer (connection details / labels /
disconnect action). The updated tree structure in the relevant region:

```
[Cluster display name]
  ...
  Custom Resources
    [API group]
      [Kind]
  Security Center
    Overview
    Images
    Resources
    Roles
  [cluster footer]
```

The section header "Security Center" is an expandable disclosure group. Its disclosure state
(expanded / collapsed) is persisted per cluster in the per-cluster view state JSON defined in
ADR-0025 and ADR-0026, alongside the other category disclosure states.

Clicking the "Security Center" header toggles the section; it does not navigate to a view.
Clicking a sub-entry opens the corresponding view in the active content area. Sub-entries do
not open tabs via `OpenTabsActor`; they are rendered directly in the content area as the
active selection, consistent with how the Overview and Events categories behave in ADR-0050.

### Sub-entry contracts

Each sub-entry is described below. All data is sourced exclusively from the Kubernetes API;
no external scanner is consulted in v1.

#### Overview

The Overview sub-entry presents a cluster security posture summary assembled from four
read-model aggregations:

- **Pods running as root** — count of `Pod` objects whose `spec.containers[*].securityContext.runAsNonRoot`
  is `false` or absent, and whose `spec.securityContext.runAsNonRoot` is also `false` or absent.
  Drill-down surfaces the pod list.
- **Namespaces missing PodSecurity admission labels** — count of `Namespace` objects without a
  `pod-security.kubernetes.io/enforce` label. Drill-down surfaces the namespace list.
- **Network policies** — count of `NetworkPolicy` objects across all namespaces. A value of 0
  is highlighted as a risk indicator. Drill-down opens the Network Policies list view.
- **mTLS-protected services** — count of `Service` objects annotated with recognised mTLS
  annotations (e.g. `networking.istio.io/exportTo` present, or Linkerd proxy injection label
  present). This count is 0 and non-highlighted when no service mesh is detected.

Empty state copy when the cluster returns zero items for all four aggregations: "No security
signals detected. Security Center reads from in-cluster API objects; scanner integration is
coming in a future release."

#### Images

The Images sub-entry presents a per-image inventory derived from the pod workload set:

- One row per unique container image reference, deduplicated across all running pods.
- Each row shows: image reference (registry / name / tag or digest), whether a digest is
  declared (a missing digest is a risk indicator), whether the base image is `distroless` or
  `scratch` (inferred from well-known registry prefixes and image name patterns), the
  `imagePullSecret` name bound to the service account of the owning pod (or "None" if absent).
- Rows are sorted by image reference alphabetically.

Empty state copy when no pods are running: "No running pods found. Start a workload to see
its image inventory here."

#### Resources

The Resources sub-entry presents a per-namespace inventory of pod resources that breach
security baselines. Each row identifies a pod or container and the specific breach:

- **Privileged container** — `spec.containers[*].securityContext.privileged == true`.
- **Host network** — `spec.hostNetwork == true`.
- **Missing resource requests** — any container with absent `resources.requests.cpu` or
  `resources.requests.memory`.
- **Missing resource limits** — any container with absent `resources.limits.cpu` or
  `resources.limits.memory`.
- **Missing readinessProbe** — any container with absent `readinessProbe`.
- **Missing livenessProbe** — any container with absent `livenessProbe`.

Rows are grouped by namespace. Within a namespace, rows are sorted by breach severity
(privileged / hostNetwork first, then missing probes, then missing resource constraints).

Empty state copy when no breaches are found: "No baseline violations detected across running
pods. Policies are evaluated against live pod specs; terminated pods are not included."

#### Roles

The Roles sub-entry presents a per-role inventory of RBAC permissions sorted by privilege
level:

- `ClusterRole` objects appear before namespaced `Role` objects.
- Within each scope, roles are sorted by privilege: roles whose rules include a verb of `*`
  (wildcard) or the verbs `impersonate` or `escalate` are listed first, labelled with a risk
  badge. The `cluster-admin` ClusterRole is always the first row.
- Each row shows: role name, scope (cluster-scoped or namespace), rule count, and a summary
  of the most privileged verb present.
- RoleBinding and ClusterRoleBinding subject counts are shown as a secondary annotation
  on each role row (e.g. "3 subjects").

Empty state copy when no roles exist (unlikely in practice but required by the empty-state
convention): "No Roles or ClusterRoles found. A minimal cluster should have at least
cluster-admin; check your cluster connectivity."

### ADR-0049 policy coverage cross-reference

ADR-0049 defines four focused Rego policies for `app_shell`:
`energy_policy.rego`, `locale_policy.rego`, `single_instance_policy.rego`,
`accessibility_policy.rego`. The Security Center sidebar surface does not introduce new
invariants requiring additional Rego policies at this time, because:

1. The Security Center views are read-only projections of Kubernetes API data; they do not
   introduce new background refresh intervals or energy-budget concerns beyond those already
   covered by `energy_policy.rego` (which governs tray widget refresh intervals, not content
   views).
2. All text in the Security Center views passes through the existing localisation layer; no new
   locale constraints arise.
3. The Security Center does not alter single-instance behaviour.
4. All new controls (disclosure group, sub-entry rows, drill-down navigation) must comply with
   the existing `accessibility_policy.rego` invariants (non-empty accessibility labels, WCAG AA
   contrast, VoiceOver order match). This compliance is achieved by following the existing
   `SidebarRowView` and `ResourceListView` accessibility patterns, not by adding a new policy.

A future ADR governing Security Center data refresh cadence (how often posture counts are
recalculated) must evaluate whether a new energy policy invariant is needed.

### Empty-state convention

Every sub-entry follows the empty-state convention established across the codebase: a centred
illustration area (SF Symbol at 40 pt, `secondary` foreground) with a title and a supporting
body paragraph. The copy for each sub-entry is defined in the sub-entry contracts above. No
action buttons appear in the empty state; the Security Center is read-only.

### Consequences

Positive:

- The Security Center section gives operators a single bookmark for routine security audits,
  matching the reference implementation surface.
- The four existing SwiftUI views (`SecurityOverviewView`, `SecurityImagesView`,
  `SecurityResourcesView`, `SecurityRolesView`) are anchored and reachable without writing new
  view code; implementation cost is primarily in `SidebarTreeViewModel` wiring and read-model
  aggregation logic.
- Deferred scanner integration keeps the v1 scope tight. No new network dependencies,
  credentials, or auth flows are introduced.
- The placement after Custom Resources and before the cluster footer is stable: it does not
  displace any existing section and has a logical position at the end of the functional
  taxonomy (posture assessment follows resource inspection).

Negative:

- The Security Center read models require additional Kubernetes API calls (pod list, namespace
  list, network policy list, RBAC list) that are not already covered by existing watch streams.
  These calls must be on-demand (triggered when the operator navigates to the section) rather
  than eagerly loaded, to avoid increasing idle API traffic.
- The mTLS-protected services count is a heuristic based on label / annotation patterns. It
  will produce false negatives for service meshes that do not use well-known annotations.
  This limitation must be documented in the UI tooltip for that count.
- The image `distroless` / `scratch` detection is pattern-based and will miss custom base
  images that happen to be minimal. This is acceptable for v1 and must be noted in the
  empty-state body text when the flag is shown.

## Pros and cons of the options

### Option A — Top-level cluster section with four sub-entries (chosen)

- Good, because a single collapsible section matches the reference implementation and
  operator mental model.
- Good, because sub-entries can be reached directly from the sidebar without opening a tab.
- Good, because disclosure state persistence reuses the existing per-cluster view state
  mechanism (no new persistence path).
- Bad, because four sub-entries are always visible when expanded; for operators who do not
  perform security audits frequently, the section adds visual noise.

### Option B — Single dashboard with internal tabs

- Good, because it reduces the sidebar item count by three entries (one header instead of
  one header plus four sub-entries).
- Bad, because it requires a new `tabKind` value in the `DocumentTab` schema defined in
  ADR-0050, complicating the tab identity contract for non-kind views.
- Bad, because it buries sub-navigation inside a tab rather than in the sidebar tree, making
  it harder to link directly to a specific security view from future features (e.g., a
  keyboard shortcut to jump directly to the Roles view).

### Option C — Scattered entries per kind family

- Good, because no new section header is needed.
- Bad, because it violates the single-canonical-entry-point requirement.
- Bad, because a security audit spanning all four views requires navigating to at least two
  separate sidebar sections, increasing interaction cost.

## Confirmation

- `SidebarTreeViewModel` adds a `securityCenter` node group after `customResources` with four
  leaf nodes: `securityOverview`, `securityImages`, `securityResources`, `securityRoles`.
- The per-cluster view state CUE schema (`contexts/app_shell/schemas/cluster_view_state.cue`)
  adds a `securityCenterExpanded: bool` field alongside the existing category disclosure flags.
- Gherkin feature `contexts/app_shell/features/security-center-tree-entry.feature` covers:
  section visible per cluster, four sub-entries in fixed order, Overview posture summary,
  Images sub-entry lists pods by image, Roles sub-entry sorts cluster-admin first.
- `SecurityOverviewViewModel`, `SecurityImagesViewModel`, `SecurityResourcesViewModel`,
  `SecurityRolesViewModel` are wired in `AppShellDependencies` and bound to their respective
  views via `@StateObject` or `@ObservedObject`.
- All new `SidebarRowView` instances must have non-empty `accessibilityLabel` values to pass
  `accessibility_policy.rego`.

## Followups

- **ADR-0069 (proposed) — Security Center scanner integration** — integrates Kubescape,
  Trivy, or Falco as optional data sources that augment the in-cluster API read models.
  Requires auth boundary definition, result schema, and refresh cadence policy.
- **Security Center data refresh cadence** — define whether posture counts auto-refresh on
  a timer (and at what interval) or are refreshed only on explicit operator action. A timer
  refresh may require a new `energy_policy.rego` invariant (see ADR-0049).
- **`cluster_view_state.cue` schema update** — add `securityCenterExpanded: bool` alongside
  existing disclosure fields. This is a non-breaking additive change.
- **Keyboard shortcut** — consider registering a keyboard shortcut to jump directly to
  Security Center Overview (e.g. `⌘⇧S`), following the pattern established in ADR-0023.

## More information

- ADR-0049 — app shell policy coverage (four focused Rego policies for `app_shell`).
- ADR-0050 — resource navigation taxonomy; defines the categorical tree and tab system that
  the Security Center section extends.
- ADR-0051 — multi-cluster workspace; defines the per-cluster sidebar tree structure and
  disclosure state persistence.
- ADR-0052 — custom resource discovery; defines the Custom Resources section that immediately
  precedes the Security Center in the sidebar tree.
- Feature gap analysis — `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`,
  item R16-b.
- Swift modules — `project/Sources/AppShell/Views/Security/SecurityOverviewView.swift`,
  `SecurityImagesView.swift`, `SecurityResourcesView.swift`, `SecurityRolesView.swift`.
