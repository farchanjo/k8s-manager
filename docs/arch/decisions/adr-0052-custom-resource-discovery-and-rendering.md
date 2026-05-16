# ADR-0052 — Custom resource discovery and rendering: dynamic CRD enumeration, API group grouping, and generic list and detail views

- Status — Accepted (ratified 2026-05-16)
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0013 (resource browser scope and supported kinds)
- Tags — crd, custom-resources, discovery, rendering, api-group, sidebar, schema, generic-view

## Context and problem statement

ADR-0013 specified a dynamic CRD enumeration flow (steps 1–5 of the discovery sequence) and noted
that CRD instances are grouped under their API group in the UI sidebar. It established the OpenAPI
v3 schema extraction path and the fallback to an untyped JSON view when no schema is present.

What ADR-0013 did not specify:

1. **Sidebar grouping structure** — how API groups are presented in the "Custom Resources" section
   of the sidebar tree (ADR-0050). Specifically: how groups with dozens of kinds are collapsed, how
   version differences within a group are surfaced, and how freshly-installed CRDs trigger a sidebar
   refresh without a full cluster reconnect.

2. **Generic list view** — the column set for a CRD instance list when no static kind-specific
   renderer exists. What columns are shown, how cell values are extracted from an untyped JSON
   response, and how the list is sorted by default.

3. **Generic detail view** — the layout for a CRD instance detail pane when the kind is unknown at
   compile time. How the OpenAPI v3 schema (if present) guides the properties grid, how absent
   schemas are handled, and how the standard action toolbar is adapted for CRD-specific constraints.

4. **Version disambiguation** — a CRD may expose multiple versions (e.g., `v1alpha1`, `v1beta1`,
   `v1`). The UI must present the preferred version to the operator and allow explicit version
   selection for advanced inspection.

5. **Watch stream for unknown kinds** — ADR-0036 defines the watch lifecycle but the kind must be
   known to the `WatchPort` adapter. For dynamically-discovered CRD kinds, the adapter must accept a
   `GroupVersionResource` (GVR) struct rather than a compile-time type.

This ADR answers all five questions and extends the ADR-0013 CRD flow with the full presentation
layer contract.

## Decision drivers

- **Operators using Argo, Flux, Cert Manager, Crossplane** expect their CRDs to be fully navigable,
  not merely listed. A generic renderer that leverages the embedded OpenAPI schema provides far more
  value than a raw JSON dump.
- **Watch stream completeness** — CRD instances should receive live updates just like standard
  kinds. A generic watch path using GVR structs avoids the need for compile-time type registration.
- **Schema-guided rendering** — when the CRD carries an OpenAPI v3 schema, the UI can render a
  structured properties grid with field descriptions. This is the primary differentiator from
  `kubectl get -o yaml`.
- **Sidebar stability** — newly installed CRDs must appear in the sidebar without requiring the
  operator to disconnect and reconnect the cluster session.
- **Version clarity** — operators who use multi-version CRDs (e.g., Argo Workflows `v1alpha1`) must
  know which version they are looking at and be able to switch.

## Considered options

- **Option A** — Schema-guided generic renderer with live watch support via GVR structs (chosen).
- **Option B** — Raw JSON viewer only; no column extraction; no schema rendering; no sidebar
  grouping beyond a flat list of discovered kinds.
- **Option C** — Skip CRD list/detail UI entirely; link to `kubectl describe` output via a terminal
  session instead.

## Decision outcome

Chosen option — **Option A**, because:

- The OpenAPI v3 schema is already extracted at discovery time (ADR-0013); not using it for
  rendering is a wasted opportunity.
- A GVR-based watch path is a straightforward extension of the existing `WatchPort` protocol.
- Option B provides no meaningful improvement over `kubectl get -o json`; it would disappoint
  operators who rely on CRD-heavy stacks.
- Option C is a regression: terminal sessions require cluster exec access; the resource browser's
  read-only watch path is safe by default.

### Sidebar grouping for Custom Resources

The "Custom Resources" section of the sidebar tree (ADR-0050) is structured as follows:

```
Custom Resources
  CRD Catalog          ← lists all CustomResourceDefinition objects
  [api-group-1]        ← collapsible section, e.g. "argoproj.io"
    ApplicationSet
    Application
    Workflow
  [api-group-2]        ← e.g. "cert-manager.io"
    Certificate
    CertificateRequest
    ClusterIssuer
    Issuer
    Order
  ...
```

Rules:

- Each discovered API group becomes one collapsible disclosure item.
- API group names are displayed verbatim (e.g., `argoproj.io`). No truncation; horizontal scroll if
  the name exceeds the sidebar column width.
- Kinds within a group are sorted alphabetically.
- Groups with zero discovered instances (empty list at display time) are shown with a count badge of
  `0` rather than being hidden. Hiding empty groups causes confusion when the operator knows a CRD
  exists but has not yet created instances.
- The disclosure state (expanded/collapsed per group) is persisted in per-cluster view state JSON.

**Live sidebar refresh** — the `ResourceDescriptorRegistry` (defined in ADR-0013) watches the
`CustomResourceDefinition` API endpoint. When a new `ADDED` or `MODIFIED` event arrives, the
registry updates the group and kind map and publishes a `CRDCatalogUpdated` domain event on the
`DomainEventBusPort`. The `app_shell` sidebar view model subscribes to this event and triggers a
`@Observable` property update, causing SwiftUI to re-render the Custom Resources section without a
full sidebar rebuild.

### Generic list view

When the operator selects a CRD kind from the sidebar, a `resourceList` tab opens (ADR-0050). The
list view renders a generic view with the following default columns:

- **Name** — extracted from `metadata.name`; flexible width.
- **Namespace** — extracted from `metadata.namespace`; blank for cluster-scoped kinds; 140 pt.
- **Age** — derived from `metadata.creationTimestamp`; 80 pt.
- **Status** — priority-ordered probe: `status.phase`, then `status.state`, then `status.ready`,
  then `—` if none present; 100 pt.

Column extraction uses a priority-ordered JSON path probe. The probe sequence is tried in order and
stops at the first non-null, non-empty value. The probe is defined in `ResourceKindDescriptor` as a
`statusFieldPaths: [String]` property.

Additional columns declared in the CRD's `spec.additionalPrinterColumns` (standard Kubernetes field)
are appended after the four default columns, in the order declared in the CRD manifest.
`additionalPrinterColumns` entries carry a `jsonPath` expression; the list view evaluates the
expression against each item using a lightweight RFC 6901 / JSONPath library.

The list is sorted by `metadata.creationTimestamp` descending on first load. The operator can click
any column header to re-sort. Sort state is not persisted.

A watch stream for the CRD kind is established via the `GVRWatchPort` extension of `WatchPort`:

```swift
/// Protocol extension for dynamically-discovered GVRs.
/// Implemented by the same adapter as WatchPort.
public protocol GVRWatchPort: Sendable {
    /// Start a watch for an arbitrary GroupVersionResource.
    /// Returns an AsyncThrowingStream of raw JSON events.
    func watch(
        gvr: GroupVersionResource,
        namespace: String?,
        resourceVersion: String
    ) -> AsyncThrowingStream<RawWatchEvent, Error>
}
```

The `GroupVersionResource` struct carries `group`, `version`, and `resource` (plural lowercase kind
name, e.g., `"applications"`).

### Generic detail view

Selecting a row in the CRD list view opens a `resourceDetail` tab and renders the detail drawer
(ADR-0051) with schema-guided or fallback rendering.

**Schema-guided rendering** (when `openAPIV3Schema` is present in the CRD):

1. Extract the schema from `spec.versions[preferredVersion].schema.openAPIV3Schema`.
2. Flatten the top-level `properties` map into a properties grid. Each property becomes one row:
   - Column 1: field name (from schema `title` if present, else the property key).
   - Column 2: field description (from schema `description`, truncated to 2 lines with expand).
   - Column 3: rendered value (from the instance JSON, formatted by schema `type`: `string` →
     verbatim; `integer`/`number` → right-aligned; `boolean` → checkmark/cross; `object` →
     expand-to-subgrid; `array` → count badge + expand).
3. Nested objects at depth > 2 are rendered as a collapsible JSON view rather than a recursive grid.
4. Fields present in the instance but absent from the schema (due to
   `x-kubernetes-preserve-unknown-fields`) are appended at the bottom of the grid under a
   "Additional fields" disclosure group.

**Fallback rendering** (no schema or `x-kubernetes-preserve-unknown-fields: true` at root):

- The full resource JSON is rendered in the YAML tab (syntax-highlighted, read-only by default).
- The Edit YAML action is still available if the operator has write permissions and the kind is in
  the mutation guard allowlist.
- The properties grid tab shows only `metadata` fields (name, namespace, labels, annotations, UID,
  creation timestamp, resource version).

**Action toolbar for CRD instances**:

- `edit-yaml` — always available (subject to mutation guard, ADR-0012).
- `delete` — always available (with double-confirm, ADR-0012).
- `scale` — available only if `spec.subresources.scale` is declared in the CRD version.
- `rollout-restart` — not available for CRD instances (requires Deployment-specific patch).
- `logs` — not available for CRD instances.
- `events` — always available; shows events whose `involvedObject.kind` matches the CRD kind.

### Version disambiguation

When a CRD declares multiple versions:

- The sidebar tree entry always resolves to the preferred version (the version marked
  `storage: true` in the CRD spec, or the first version if none is marked).
- A version picker chip appears in the detail drawer header when multiple versions exist. Clicking
  it opens a dropdown listing all versions; the selected version is used for `get` and `watch` calls
  until the tab is closed.
- The version selection is stored in the tab's contextual identifiers (`selectedVersion?: String`).
- Version mismatches (e.g., the instance was created under `v1alpha1` and the cluster has migrated
  to `v1`) surface a banner in the detail drawer: "This resource was created under version
  `v1alpha1`; displaying under `v1` (storage version)."

### CRDCatalogUpdated domain event

```
eventType: "resource_browser.CRDCatalogUpdated"
sourceContext: "resource_browser"
payload:
  clusterId: string (UUIDv7)
  addedGroups: [string]
  removedGroups: [string]
  addedKinds: [{group, kind, preferredVersion}]
  removedKinds: [{group, kind}]
  catalogVersion: int (monotonically increasing)
```

This event is emitted on every watch event for `CustomResourceDefinition`. Consumers:

- `app_shell` — refreshes the Custom Resources sidebar section.
- `analytics_dashboard` — updates CRD count metrics (if tracked).

### Consequences

Positive:

- Operators using CRD-heavy stacks (Argo, Flux, Cert Manager, Crossplane) get full list and detail
  views with live updates.
- Schema-guided rendering turns the detail pane into a self-documenting interface for unknown kinds.
- Live sidebar refresh via `CRDCatalogUpdated` eliminates the need for manual reconnection.
- `GVRWatchPort` provides a clean extension point without breaking the compile-time `WatchPort`
  protocol for standard kinds.

Negative:

- JSONPath evaluation for `additionalPrinterColumns` requires a client-side implementation or a
  lightweight library; this is a net-new dependency that must be vetted for security.
- Schema-guided rendering depth is limited to 2 levels for performance; deeply nested CRD schemas
  degrade to JSON view, which may surprise operators.
- The `CRDCatalogUpdated` event adds to the domain event taxonomy (ADR-0040); the event schema must
  be maintained in `domain_events.cue`.

## Pros and cons of the options

### Option A — Schema-guided generic renderer with live watch (chosen)

- Good, because OpenAPI v3 schemas are extracted at discovery time; rendering them costs no
  additional API calls.
- Good, because the `GVRWatchPort` extension is a minimal protocol addition that reuses the existing
  watch lifecycle state machine (ADR-0036).
- Good, because `additionalPrinterColumns` are a standard Kubernetes mechanism; supporting them
  aligns with the platform.
- Bad, because schema rendering complexity is higher than a simple JSON dump; incorrect rendering
  must be caught by integration tests.

### Option B — Raw JSON viewer only

- Good, because implementation complexity is minimal.
- Bad, because raw JSON provides no ergonomic improvement over `kubectl get -o json`.
- Bad, because the sidebar grouping by API group is still required regardless, so the work is not
  fully avoided.

### Option C — Terminal session only

- Good, because it leverages existing terminal infrastructure.
- Bad, because terminal sessions require exec access; read-only watch paths are safer.
- Bad, because it provides no structured rendering, no live list, and no action toolbar.

## Confirmation

- `contexts/resource_browser/schemas/resource_descriptor.cue` is extended with `statusFieldPaths`
  and `crdOpenAPISchema` fields for dynamic kinds.
- `contexts/_shared/schemas/domain_events.cue` is extended with `#CRDCatalogUpdated`.
- `contexts/app_shell/features/resource-kind-catalog-discovery.feature` covers: CRD discovery adds
  group to sidebar, `CRDCatalogUpdated` event triggers sidebar refresh, removed CRD group disappears
  from sidebar, `additionalPrinterColumns` are rendered in list view.
- A unit test for the JSONPath evaluator verifies extraction of common `additionalPrinterColumns`
  patterns (`.spec.replicas`, `.status.phase`, `.metadata.labels.app`).
- An integration test installs a mock CRD, verifies that the sidebar adds the group, opens a list
  tab, and verifies that the generic list renders the correct column values.
- An integration test exercises schema-guided rendering: a CRD with an embedded OpenAPI v3 schema is
  installed; the detail view is opened; the properties grid shows the schema `title` and
  `description` for each top-level field.

## More information

- ADR-0013 — Original CRD discovery flow (steps 1–5). This ADR extends the presentation layer only;
  the discovery sequence is unchanged.
- ADR-0036 — Watch stream lifecycle; `GVRWatchPort` uses the same state machine (LIST then WATCH,
  bookmark handling, 410-Gone recovery, exponential backoff).
- ADR-0040 — Domain event taxonomy; `CRDCatalogUpdated` event added.
- ADR-0050 — Resource navigation taxonomy; Custom Resources sidebar section structure.
- ADR-0051 — Multi-cluster workspace; detail drawer layout used for CRD instance detail.
