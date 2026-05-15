# ADR-0013 — Resource browser scope and supported Kubernetes kinds

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — resource-browser, kinds, gvk, operations, crds, scope

## Context and problem statement

The `resource_browser` bounded context (introduced in ADR-0005 and expanded in ADR-0006) requires a
canonical catalogue of the Kubernetes resource kinds it supports in the MVP+ release. Without an
explicit catalogue, the implementation risks either under-delivering (only a handful of kinds) or
over-scoping (every discoverable GVK, including third-party ones that require special handling).

A second concern is operation surface. The API verbs available for a given kind vary — not every
kind supports `scale`, logs are meaningful only for `Pod`, `exec` is a separate capability requiring
explicit security controls. The catalogue must map each kind to its permitted operations so that the
UI can compose the correct toolbar and context menu, and the mutation guard can enforce the closed
set.

A third concern is CRDs. The application must discover `CustomResourceDefinition` instances
dynamically and enumerate their instances as first-class resources, but the operation surface for
CRD instances is necessarily narrower than for core kinds.

This ADR establishes the kind catalogue, the per-kind operation surface, and the boundaries for MVP+
versus future milestones.

## Decision drivers

- **Coverage of the 80% case** — the kinds listed here cover the workloads, networking, storage,
  access control, and extension objects that operators interact with on a daily basis.
- **No accidental exec surface** — `exec` into a container opens a pty with broad cluster access; it
  must not appear by default in the MVP+ toolbar. It is listed as a future capability.
- **Dynamic CRD enumeration** — operators who use Argo, Flux, Cert Manager, or other operators
  expect to see their custom resources; static enumeration is insufficient.
- **Audit coverage** — every mutation operation must be captured in `cluster_mutation_audit`
  (ADR-0012); the kind catalogue defines the universe of allowed targets.
- **SwiftkubeClient fidelity** — the chosen adapter (ADR-0002) generates typed Swift structs for
  well-known API groups; the catalogue must align with the types that `swiftkube/client 0.26` can
  materialise.

## Considered options

- **Option A** — Explicit closed-set catalogue with dynamic CRD extension (chosen).
- **Option B** — Fully dynamic discovery; enumerate all GVKs via `/apis` and `/api` at runtime; no
  static catalogue.
- **Option C** — Minimal catalogue (workloads and config only; no RBAC, no storage, no networking,
  no CRDs).

## Decision outcome

Chosen option — **Option A**, because a static catalogue for well-known kinds gives the UI, the
policy engine, and the test suite a stable surface to target, while dynamic CRD discovery covers the
long tail without requiring a catalogue update per third-party operator.

### Kind catalogue for MVP+

Each entry lists: API group/version, kind name, namespaced flag, and the permitted operations.

Permitted operations are drawn from the closed set: `list`, `get`, `watch`, `edit-yaml`, `delete`,
`scale`, `rollout-restart`, `logs`, `events`.

#### core/v1

- `Pod` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`, `logs`, `events`.
- `Service` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`, `events`.
- `ConfigMap` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`.
- `Secret` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`. Value display is
  redacted by default; operator must explicitly reveal each value.
- `Endpoints` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`.
- `PersistentVolumeClaim` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`,
  `events`.
- `PersistentVolume` — cluster-scoped. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`,
  `events`.
- `Namespace` — cluster-scoped. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`, `events`.
- `ServiceAccount` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`.

#### apps/v1

- `Deployment` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`, `scale`,
  `rollout-restart`, `events`.
- `DaemonSet` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`,
  `rollout-restart`, `events`.
- `StatefulSet` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`, `scale`,
  `rollout-restart`, `events`.
- `ReplicaSet` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`, `scale`,
  `events`.

#### batch/v1

- `Job` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`, `events`.
- `CronJob` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`, `events`.

#### networking.k8s.io/v1

- `Ingress` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`, `events`.
- `NetworkPolicy` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`.

#### storage.k8s.io/v1

- `StorageClass` — cluster-scoped. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`.

#### rbac.authorization.k8s.io/v1

- `Role` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`.
- `RoleBinding` — namespaced. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`.
- `ClusterRole` — cluster-scoped. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`.
- `ClusterRoleBinding` — cluster-scoped. Operations: `list`, `get`, `watch`, `edit-yaml`, `delete`.

#### apiextensions.k8s.io/v1

- `CustomResourceDefinition` — cluster-scoped. Operations: `list`, `get`, `watch`, `edit-yaml`,
  `delete`, `events`.
- CRD instances (dynamic) — namespaced or cluster-scoped per `spec.scope`. Operations: `list`,
  `get`, `watch`, `edit-yaml`, `delete`, `events`. No `scale` or `rollout-restart` unless the CRD
  declares the `/scale` subresource.

### CRDs versus aggregated APIs

The Kubernetes extension mechanism has two distinct pathways that the resource browser must handle
differently.

**Custom Resource Definitions (CRDs)** are registered through the `apiextensions.k8s.io/v1` API
group. The authoritative resource is `CustomResourceDefinition` at the path
`/apis/apiextensions.k8s.io/v1/customresourcedefinitions`. Each CRD carries an embedded OpenAPI v3
schema at `spec.versions[].schema.openAPIV3Schema`. The resource browser renders this schema in the
editor panel to provide field-level documentation and validation hints for CRD instances. The schema
is extracted once at CRD discovery time and cached in the resource descriptor registry. If a CRD
version does not carry a schema (the field is absent or `x-kubernetes-preserve-unknown-fields: true`
is set at the root), the editor falls back to an untyped JSON view.

**Aggregated APIs** are registered through the `apiregistration.k8s.io/v1` API group as `APIService`
objects. Each `APIService` describes a backend service that handles requests for one API group and
version. Aggregated APIs differ from CRDs in two critical ways:

- Their backend is a separate process (not the Kubernetes API server) and may be unavailable. The
  `APIService` object carries a `status` block with a `conditions` list; the condition type
  `Available` with status `False` indicates the backend is down. The resource browser checks this
  condition before attempting to list resources for an aggregated API group.
- Resource discovery via `GET /apis/<group>/<version>` may return `503 Service Unavailable` if the
  backend is offline. The adapter must treat `503` on a discovery request as a transient backend
  health failure, not a protocol error. Affected kinds are shown in the UI with an `unavailable`
  badge rather than an error state.

**Discovery flow.** The resource descriptor registry is populated via the following sequence on each
cluster connection:

1. `GET /apis` — returns the `APIGroupList`. Each entry carries `name` (group), `versions[]`
   (available versions), and `preferredVersion`. This call enumerates all API groups including those
   served by aggregated backends.
2. For each group and preferred version, `GET /apis/<group>/<version>` — returns an
   `APIResourceList` enumerating the resource kinds, verbs, namespaced flag, and subresources for
   that group/version.
3. `GET /apis/apiregistration.k8s.io/v1/apiservices` — returns all registered `APIService` objects.
   The resource descriptor registry cross-references each discovered group/version against this list
   to determine whether it is served by an aggregated backend.
4. For any group/version backed by an `APIService` whose `Available` condition is `False`, all
   resource kinds in that group/version are flagged `backendUnavailable: true` in the registry.
5. The `apiextensions.k8s.io/v1/customresourcedefinitions` list is fetched and each CRD is
   registered with its embedded OpenAPI schema.

Steps 1–5 are executed in parallel using a `TaskGroup` to minimise connection time. Steps 3–5 may
return partial results if individual backend services are unavailable; partial results are accepted
and the unavailability is surfaced in the UI.

The registry is refreshed on every WATCH event for `CustomResourceDefinition` (new CRD added or
existing CRD deleted) and on every WATCH event for `APIService` (backend health change).

### Dynamic CRD enumeration

At connection time the application fetches the full list of `CustomResourceDefinition` objects from
the cluster and registers each discovered GVK in the resource descriptor registry as described in
the discovery flow above. The registry is held in the `resource_browser` domain and refreshed on
every watch event for the `CustomResourceDefinition` kind.

The UI sidebar groups CRD instances under their API group. The operator can filter by group name.

CRD instances whose underlying CRD is later deleted from the cluster are removed from the registry
on the next refresh. An in-flight list or watch for a removed CRD emits a `kindUnavailable` event
and the UI surfaces an inline error row.

### Server-side apply, conflict resolution, and YAML diff preview

All edit-yaml operations use server-side apply as specified in ADR-0012. The field manager is
`com.archanjo.K8sManager`. Conflict resolution and YAML diff preview behave as specified in
ADR-0012.

### Operations out of scope for MVP+

- `exec` — container shell access requires a pty-level UX and security controls beyond the current
  scope. Deferred.
- `port-forward` — deferred to a future milestone.
- Bulk select and bulk delete — deferred.
- Helm install, upgrade, rollback — deferred to the `helm_management` bounded context (future ADR).
- Custom columns and field selectors in the list view — deferred.

### Consequences

- **Positive** — a closed-set catalogue enables static typing via SwiftkubeClient's generated types
  for core kinds; the mutation guard can enforce the allowlist at the Rego layer; the UI can compose
  a correct per-kind toolbar without runtime inspection.
- **Negative** — new API groups introduced by future Kubernetes versions require an explicit
  catalogue update; CRD operations are narrower than core-kind operations, which may disappoint
  operators who use CRD-based controllers with rich subresource support.
- **Neutral** — the dynamic CRD path uses untyped JSON via the Kubernetes discovery API; the domain
  model projects this into `#ResourceDetail` with a raw JSON payload plus parsed conditions and
  events.

### Confirmation

- The `resource_descriptor.cue` schema enumerates a `supportedVerbs` closed set and is validated in
  CI.
- A unit test for the resource descriptor registry verifies that each kind in this catalogue is
  registered with the correct `namespaced` flag and `supportedVerbs` set.
- An integration test issues a `list` call against a kind-n-fly cluster (k3d or kind) for each
  static kind in the catalogue and asserts that the response decodes without error.
- An integration test fetches the CRD list from the same cluster, registers any discovered CRD, and
  verifies that instances of that CRD appear in the list view, with the OpenAPI v3 schema extracted
  from `spec.versions[].schema.openAPIV3Schema` and stored in the registry.
- An integration test registers a mock `APIService` with `Available: False` and verifies that all
  resource kinds in the corresponding group/version carry `backendUnavailable: true` in the
  registry, and that the UI renders an `unavailable` badge rather than a list.
- A unit test exercises the discovery flow (steps 1–5) against mock HTTP responses and verifies that
  the `TaskGroup` parallel execution produces a fully populated registry even when step 3 returns a
  503 for one of the API services.
- A smoke test opens the resource browser for each kind in the catalogue and asserts that the
  toolbar shows exactly the operations declared in this ADR.
- A unit test verifies that a CRD without an embedded OpenAPI schema (root
  `x-kubernetes-preserve-unknown-fields: true`) causes the editor to render an untyped JSON view
  rather than a schema-validated form.

## Pros and cons of the options

### Option A — Closed-set catalogue with dynamic CRD extension (chosen)

- **Pros** — stable surface for testing and UI composition; dynamic CRD extension covers third-party
  operators; kind-level operation constraints are expressible in the mutation guard Rego policy;
  aligns with SwiftkubeClient 0.26 generated types.
- **Cons** — catalogue must be updated when new well-known API groups are added to Kubernetes;
  operator preferences for additional kinds (e.g., `HorizontalPodAutoscaler`) cannot be satisfied
  until the catalogue is extended.

### Option B — Fully dynamic discovery

- **Pros** — zero catalogue maintenance; every present API group is automatically available.
- **Cons** — the mutation guard cannot enforce a closed set of allowed kinds without re-implementing
  the catalogue at the policy layer; the UI cannot compose kind-specific toolbars without runtime
  introspection; SwiftkubeClient typed structs are bypassed entirely for non-core kinds; the
  operation surface for unknown kinds defaults to the lowest common denominator.

### Option C — Minimal catalogue (workloads and config only)

- **Pros** — smallest implementation surface; easiest to ship.
- **Cons** — omits RBAC, storage, networking, and CRDs, which are all required for meaningful
  day-to-day cluster management; a minimal browser is not a meaningful advancement over
  `kubectl get`.

## More information

- ADR-0002 — SwiftkubeClient adapter; generated types align with the API groups listed in this
  catalogue.
- ADR-0005 — `resource_browser` is a first-class bounded context.
- ADR-0006 — MVP+ scope explicitly includes resource editing and mutation operations.
- ADR-0012 — Mutating operations policy; the kind catalogue defines the universe of allowed mutation
  targets.
- Kubernetes API reference for each group/version/kind combination referenced above:
  kubernetes.io/docs/reference/kubernetes-api/.
