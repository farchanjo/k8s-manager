# ADR-0013 — Resource browser scope and supported Kubernetes kinds

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — resource-browser, kinds, gvk, operations, crds, scope

## Context and problem statement

The `resource_browser` bounded context (introduced in ADR-0005 and
expanded in ADR-0006) requires a canonical catalogue of the Kubernetes
resource kinds it supports in the MVP+ release. Without an explicit
catalogue, the implementation risks either under-delivering (only a
handful of kinds) or over-scoping (every discoverable GVK, including
third-party ones that require special handling).

A second concern is operation surface. The API verbs available for a
given kind vary — not every kind supports `scale`, logs are
meaningful only for `Pod`, `exec` is a separate capability requiring
explicit security controls. The catalogue must map each kind to its
permitted operations so that the UI can compose the correct toolbar
and context menu, and the mutation guard can enforce the closed set.

A third concern is CRDs. The application must discover
`CustomResourceDefinition` instances dynamically and enumerate their
instances as first-class resources, but the operation surface for CRD
instances is necessarily narrower than for core kinds.

This ADR establishes the kind catalogue, the per-kind operation
surface, and the boundaries for MVP+ versus future milestones.

## Decision drivers

- **Coverage of the 80% case** — the kinds listed here cover the
  workloads, networking, storage, access control, and extension
  objects that operators interact with on a daily basis.
- **No accidental exec surface** — `exec` into a container opens a
  pty with broad cluster access; it must not appear by default in
  the MVP+ toolbar. It is listed as a future capability.
- **Dynamic CRD enumeration** — operators who use Argo, Flux, Cert
  Manager, or other operators expect to see their custom resources;
  static enumeration is insufficient.
- **Audit coverage** — every mutation operation must be captured
  in `cluster_mutation_audit` (ADR-0012); the kind catalogue defines
  the universe of allowed targets.
- **SwiftkubeClient fidelity** — the chosen adapter (ADR-0002)
  generates typed Swift structs for well-known API groups; the
  catalogue must align with the types that `swiftkube/client 0.26`
  can materialise.

## Considered options

- **Option A** — Explicit closed-set catalogue with dynamic CRD
  extension (chosen).
- **Option B** — Fully dynamic discovery; enumerate all GVKs via
  `/apis` and `/api` at runtime; no static catalogue.
- **Option C** — Minimal catalogue (workloads and config only;
  no RBAC, no storage, no networking, no CRDs).

## Decision outcome

Chosen option — **Option A**, because a static catalogue for
well-known kinds gives the UI, the policy engine, and the test suite
a stable surface to target, while dynamic CRD discovery covers the
long tail without requiring a catalogue update per third-party
operator.

### Kind catalogue for MVP+

Each entry lists: API group/version, kind name, namespaced flag,
and the permitted operations.

Permitted operations are drawn from the closed set:
`list`, `get`, `watch`, `edit-yaml`, `delete`, `scale`,
`rollout-restart`, `logs`, `events`.

#### core/v1

- `Pod` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`, `logs`, `events`.
- `Service` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`, `events`.
- `ConfigMap` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`.
- `Secret` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`. Value display is redacted by default;
  operator must explicitly reveal each value.
- `Endpoints` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`.
- `PersistentVolumeClaim` — namespaced. Operations: `list`, `get`,
  `watch`, `edit-yaml`, `delete`, `events`.
- `PersistentVolume` — cluster-scoped. Operations: `list`, `get`,
  `watch`, `edit-yaml`, `delete`, `events`.
- `Namespace` — cluster-scoped. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`, `events`.
- `ServiceAccount` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`.

#### apps/v1

- `Deployment` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`, `scale`, `rollout-restart`, `events`.
- `DaemonSet` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`, `rollout-restart`, `events`.
- `StatefulSet` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`, `scale`, `rollout-restart`, `events`.
- `ReplicaSet` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`, `scale`, `events`.

#### batch/v1

- `Job` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`, `events`.
- `CronJob` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`, `events`.

#### networking.k8s.io/v1

- `Ingress` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`, `events`.
- `NetworkPolicy` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`.

#### storage.k8s.io/v1

- `StorageClass` — cluster-scoped. Operations: `list`, `get`,
  `watch`, `edit-yaml`, `delete`.

#### rbac.authorization.k8s.io/v1

- `Role` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`.
- `RoleBinding` — namespaced. Operations: `list`, `get`, `watch`,
  `edit-yaml`, `delete`.
- `ClusterRole` — cluster-scoped. Operations: `list`, `get`,
  `watch`, `edit-yaml`, `delete`.
- `ClusterRoleBinding` — cluster-scoped. Operations: `list`, `get`,
  `watch`, `edit-yaml`, `delete`.

#### apiextensions.k8s.io/v1

- `CustomResourceDefinition` — cluster-scoped. Operations: `list`,
  `get`, `watch`, `edit-yaml`, `delete`, `events`.
- CRD instances (dynamic) — namespaced or cluster-scoped per
  `spec.scope`. Operations: `list`, `get`, `watch`, `edit-yaml`,
  `delete`, `events`. No `scale` or `rollout-restart` unless the
  CRD declares the `/scale` subresource.

### Dynamic CRD enumeration

At connection time the application fetches the full list of
`CustomResourceDefinition` objects from the cluster and registers
each discovered GVK in the resource descriptor registry. The
registry is held in the `resource_browser` domain and refreshed
on every watch event for the `CustomResourceDefinition` kind.

The UI sidebar groups CRD instances under their API group. The
operator can filter by group name.

CRD instances whose underlying CRD is later deleted from the cluster
are removed from the registry on the next refresh. An in-flight
list or watch for a removed CRD emits a `kindUnavailable` event and
the UI surfaces an inline error row.

### Server-side apply, conflict resolution, and YAML diff preview

All edit-yaml operations use server-side apply as specified in
ADR-0012. The field manager is `com.archanjo.K8sManager`. Conflict
resolution and YAML diff preview behave as specified in ADR-0012.

### Operations out of scope for MVP+

- `exec` — container shell access requires a pty-level UX and
  security controls beyond the current scope. Deferred.
- `port-forward` — deferred to a future milestone.
- Bulk select and bulk delete — deferred.
- Helm install, upgrade, rollback — deferred to the
  `helm_management` bounded context (future ADR).
- Custom columns and field selectors in the list view — deferred.

### Consequences

- **Positive** — a closed-set catalogue enables static typing via
  SwiftkubeClient's generated types for core kinds; the mutation
  guard can enforce the allowlist at the Rego layer; the UI can
  compose a correct per-kind toolbar without runtime inspection.
- **Negative** — new API groups introduced by future Kubernetes
  versions require an explicit catalogue update; CRD operations are
  narrower than core-kind operations, which may disappoint operators
  who use CRD-based controllers with rich subresource support.
- **Neutral** — the dynamic CRD path uses untyped JSON via the
  Kubernetes discovery API; the domain model projects this into
  `#ResourceDetail` with a raw JSON payload plus parsed conditions
  and events.

### Confirmation

- The `resource_descriptor.cue` schema enumerates a `supportedVerbs`
  closed set and is validated in CI.
- A unit test for the resource descriptor registry verifies that each
  kind in this catalogue is registered with the correct `namespaced`
  flag and `supportedVerbs` set.
- An integration test issues a `list` call against a kind-n-fly
  cluster (k3d or kind) for each static kind in the catalogue and
  asserts that the response decodes without error.
- An integration test fetches the CRD list from the same cluster,
  registers any discovered CRD, and verifies that instances of that
  CRD appear in the list view.
- A smoke test opens the resource browser for each kind in the
  catalogue and asserts that the toolbar shows exactly the operations
  declared in this ADR.

## Pros and cons of the options

### Option A — Closed-set catalogue with dynamic CRD extension (chosen)

- **Pros** — stable surface for testing and UI composition; dynamic
  CRD extension covers third-party operators; kind-level operation
  constraints are expressible in the mutation guard Rego policy;
  aligns with SwiftkubeClient 0.26 generated types.
- **Cons** — catalogue must be updated when new well-known API groups
  are added to Kubernetes; operator preferences for additional kinds
  (e.g., `HorizontalPodAutoscaler`) cannot be satisfied until the
  catalogue is extended.

### Option B — Fully dynamic discovery

- **Pros** — zero catalogue maintenance; every present API group is
  automatically available.
- **Cons** — the mutation guard cannot enforce a closed set of
  allowed kinds without re-implementing the catalogue at the policy
  layer; the UI cannot compose kind-specific toolbars without
  runtime introspection; SwiftkubeClient typed structs are bypassed
  entirely for non-core kinds; the operation surface for unknown
  kinds defaults to the lowest common denominator.

### Option C — Minimal catalogue (workloads and config only)

- **Pros** — smallest implementation surface; easiest to ship.
- **Cons** — omits RBAC, storage, networking, and CRDs, which are
  all required for meaningful day-to-day cluster management; a minimal
  browser is not a meaningful advancement over `kubectl get`.

## More information

- ADR-0002 — SwiftkubeClient adapter; generated types align with
  the API groups listed in this catalogue.
- ADR-0005 — `resource_browser` is a first-class bounded context.
- ADR-0006 — MVP+ scope explicitly includes resource editing and
  mutation operations.
- ADR-0012 — Mutating operations policy; the kind catalogue defines
  the universe of allowed mutation targets.
- Kubernetes API reference for each group/version/kind combination
  referenced above: kubernetes.io/docs/reference/kubernetes-api/.
