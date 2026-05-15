# ADR-0012 — Mutating operations policy for cluster resources

- Status — Proposed; supersedes the "no cluster write" restriction in ADR-0003
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — mutations, safety, ux, audit, server-side-apply, conflict-resolution

## Context and problem statement

ADR-0003 declared that K8sManager is read-only against Kubernetes clusters. That restriction was
appropriate for the MVP scope, which covered connectivity and context switching only. ADR-0006
introduced the `resource_browser` bounded context into the MVP+ roadmap. That context is the natural
home for resource editing, scaling, rollout restarts, and delete operations.

The question is no longer whether the application should mutate clusters at all — the product
direction has settled that it should — but rather under what conditions, with what safeguards, and
with what audit obligations mutations are permitted.

This ADR narrows the read-only restriction of ADR-0003 to the credential layer (kubeconfig is still
never written; cluster credentials are still never persisted) and establishes a complete safety
policy for cluster resource mutations within the `resource_browser` context.

The secondary question is whether the LLM assistant (`cluster_intelligence`) should gain mutating
tools. This ADR explicitly defers that capability and keeps the assistant read-only until a separate
ADR is approved.

## Decision drivers

- **Explicit operator intent** — every mutation must originate from a deliberate UI gesture; no
  implicit, scheduled, or background mutations.
- **Reversibility awareness** — operators must understand what will change before it changes; YAML
  diff preview is mandatory for apply operations.
- **Double-confirm for irreversible operations** — delete is the clearest case; the operator must
  confirm twice and must type the resource name to proceed.
- **Field manager accountability** — every server-side apply (SSA) operation must carry a fixed,
  recognisable `fieldManager` identifier so that ownership conflicts are traceable to this
  application.
- **Audit trail** — every mutation attempt (succeeded, denied, failed, or cancelled) must be
  persisted to SQLite before the API call is dispatched, enabling forensic review.
- **Conflict resolution is opt-in** — the application defaults to standard SSA conflict detection;
  forcing ownership over conflicting fields is an explicit operator opt-in, not the default.
- **Assistant remains read-only** — the LLM assistant context (`cluster_intelligence`) does not
  receive mutating tools in this release cycle. Safety requirements for LLM-driven mutations are a
  separate decision.
- **Kubeconfig immutability preserved** — nothing in this ADR alters the read-only treatment of
  kubeconfig files and cluster credentials established in ADR-0003.

## Considered options

- **Option A** — Full CRUD with explicit confirmation (chosen).
- **Option B** — Conservative write subset (apply and scale only; no delete; no label/annotation
  patch).
- **Option C** — Remain read-only; defer all mutations to a future release.

## Decision outcome

Chosen option — **Option A**, because it delivers the full operator value of a Kubernetes manager,
the safety policy is sufficient to prevent accidental mutations, and the audit log satisfies the
accountability requirement.

### Mutation scope

The `resource_browser` context is permitted to issue the following classes of Kubernetes API
mutations. Each verb listed here must appear in
`contexts/resource_browser/policies/mutation_guard.rego` and carry a `resourceVersion` optimistic
concurrency check. The API server rejects any mutation where the submitted `resourceVersion` does
not match the current etcd version of the object; the adapter must surface this as a
`#ConflictError` and prompt the operator to refresh before retrying.

Every audit entry carries a `requestId` field (UUIDv7) generated at command construction time. Any
replayed submission with an `requestId` that already exists in `cluster_mutation_audit` is detected
as a duplicate and rejected before the API call is dispatched.

- **Apply** — server-side apply via `PATCH` with `Content-Type: application/apply-patch+yaml` and
  field manager `com.archanjo.K8sManager`. Supported for all kinds in the `resource_browser`
  allowlist. Requires single confirm.
- **Scale** — `PATCH` on the `/scale` subresource for `Deployment`, `StatefulSet`, and `ReplicaSet`.
  Represented as an `#ApplyYAML` command targeting the scale sub-resource, or as a dedicated
  `#ScaleReplicas` command. Requires single confirm.
- **Scale-to-zero** — a specialisation of `#ScaleReplicas` where the target replica count is 0.
  Carries `requiresDoubleConfirm: false` in the policy, but the UI must display a prominent warning
  that the workload will be unavailable. Mutation verb label: `scale-to-0`.
- **Rollout restart** — `PATCH` on the `spec.template.metadata.annotations` field, injecting
  `kubectl.kubernetes.io/restartedAt` with an RFC3339 timestamp. Supported for `Deployment`,
  `DaemonSet`, and `StatefulSet`. Requires single confirm.
- **Delete** — `DELETE` verb on namespaced and cluster-scoped resources. Subject to double-confirm
  and grace-period selection. `requiresDoubleConfirm: true`.
- **Evict** — `POST` to the `pods/eviction` subresource
  (`/api/v1/namespaces/{ns}/pods/{name}/eviction`) with a `policy/v1 Eviction` body. Respects
  `PodDisruptionBudget` limits; the API server returns `429 Too Many Requests` if the eviction would
  violate the PDB. The adapter surfaces `429` as `#EvictionBlocked` with the PDB name.
  `requiresDoubleConfirm: true`. Mutation verb label: `evict`.
- **Force-delete** — `DELETE` with `gracePeriodSeconds=0` in the query string. Bypasses the pod
  termination grace period and removes the object from etcd immediately.
  `requiresDoubleConfirm: true`. The UI must display an explicit warning that force-delete can leave
  volumes mounted and processes running on the node. Mutation verb label: `force-delete`.
- **Cordon / Uncordon** — `PATCH` on `Node.spec.unschedulable` (strategic merge patch:
  `{"spec":{"unschedulable":true}}` / `{"spec":{"unschedulable":null}}`). Requires single confirm.
  Mutation verb labels: `cordon`, `uncordon`.
- **Finalizer-patch** — `PATCH` on `metadata.finalizers` (strategic merge patch or JSON merge
  patch). Removing a finalizer bypasses the controller that registered it and can leave associated
  external resources (volumes, cloud load balancers, DNS records) orphaned.
  `requiresDoubleConfirm: true`. The UI must display a warning listing the finalizers that will be
  removed. Mutation verb label: `finalizer-patch`.
- **Image-change** — `PATCH` on one or more `spec.containers[].image` fields (strategic merge
  patch). Replaces the container image for a running workload without a full apply. Requires single
  confirm. Mutation verb label: `image-change`.
- **RBAC mutation** — `PATCH` or `PUT` targeting `Role`, `ClusterRole`, `RoleBinding`, or
  `ClusterRoleBinding`. Modifying RBAC objects can grant or revoke cluster access.
  `requiresDoubleConfirm: true`. Mutation verb label: `rbac-mutation`.
- **Label patch** — strategic merge patch on `metadata.labels` only. Represented as `#LabelPatch`.
  Requires single confirm.
- **Annotation patch** — strategic merge patch on `metadata.annotations` only. Represented as
  `#AnnotationPatch`. Requires single confirm.

Drain is explicitly out of scope for this ADR. Drain is a multi-step orchestration that comprises a
cordon followed by an eviction loop with PDB awareness, retry, and timeout management. It is not a
single Kubernetes API verb and cannot be represented as an atomic mutation command. Drain support is
deferred to a future ADR in the `helm_management` or `resource_browser` context. Until that ADR is
accepted, the UI must not offer a "Drain" action.

### Confirmation requirements

Every mutation requires at least one layer of explicit operator confirmation:

- **Single confirm** — a modal sheet presents the mutation summary (kind, name, namespace, verb) and
  a diff preview (for apply) before the API call is dispatched. The operator must press a labelled
  destructive-action button ("Apply", "Scale", "Restart"). Dismiss cancels with no API call made.
- **Double confirm** — required for the verbs marked `requiresDoubleConfirm: true` in the mutation
  scope above: `delete`, `evict`, `force-delete`, `finalizer-patch`, and `rbac-mutation`. The
  double-confirm modal presents the resource identity and a plain-language description of the
  irreversible consequence, then requires the operator to type the exact resource name into a text
  field before the action button becomes enabled. A second tap on the action button issues the API
  call. Typing the resource name is mandatory; clipboard paste is permitted.

### YAML diff preview

Before any `#ApplyYAML` operation is dispatched, the application fetches the live server manifest
(`GET` with `Accept: application/yaml`), diffs it against the proposed manifest using a structured
three-way merge algorithm, and renders the diff inline in the confirmation modal. Lines present only
in the live manifest are shown as removed; lines present only in the proposed manifest are shown as
added; unchanged lines are collapsed.

If the live manifest cannot be fetched (e.g., the resource does not yet exist), the diff is shown as
a pure addition.

### Server-side apply and field manager

All apply operations use server-side apply (SSA). The field manager identifier is
`com.archanjo.K8sManager`. The application never uses client-side apply
(`kubectl.kubernetes.io/last-applied-configuration`).

Default behaviour on conflict is to surface the conflicting field paths to the operator and refuse
to proceed. The operator may opt in to force ownership via a labelled toggle ("Force ownership —
take over conflicting fields") in the diff preview modal. Force ownership re-issues the same `PATCH`
with `force=true`. A prominent warning label accompanies the toggle.

### Audit log

Every mutation command, including cancellations, is written to the `cluster_mutation_audit` SQLite
table (owned by the `local_persistence` context) before the API call is dispatched. The schema is
captured in `contexts/resource_browser/schemas/mutation_audit_entry.cue`.

Mandatory fields:

- `id` — UUIDv7 generated at command construction time.
- `requestedAt` — RFC3339 timestamp of command construction.
- `kubernetesContextId` — UUIDv7 of the active cluster context.
- `command` — the serialised `#MutationCommand` sum type.
- `outcome` — one of `succeeded`, `denied`, `failed`, `cancelled`.
- `kubernetesStatusCode` — the HTTP status code returned by the API server, if an API call was made.
- `manifestDigest` — SHA-256 of the YAML sent in the request body, for apply operations.
- `confirmationToken` — the UUIDv7 generated in the confirmation modal, linking the audit entry to
  the operator gesture.

The audit table is append-only. Rows are never updated or deleted by the application. A future ADR
may introduce a retention policy.

**Tamper-evidence hash chain (MEDIUM-01).** Each audit entry carries a `previousEntryDigest` field
containing the SHA-256 hex digest of the immediately preceding row's canonical serialised form (the
UTF-8 JSON encoding of all fields in their schema-defined order, excluding `previousEntryDigest`
itself). The first row stores the sentinel value
`"0000000000000000000000000000000000000000000000000000000000000000"` (64 zero hex characters). Any
retroactive modification of a row invalidates the digest of every subsequent row, making tampering
detectable.

A SQLite trigger enforces immutability at the database level:

```sql
CREATE TRIGGER cluster_mutation_audit_immutable
BEFORE UPDATE OR DELETE ON cluster_mutation_audit
BEGIN
  SELECT RAISE(ABORT, 'audit_immutable');
END;
```

This trigger is installed by the initial migration and must not be dropped or disabled by any
subsequent migration. Integration tests that attempt an `UPDATE` or `DELETE` on
`cluster_mutation_audit` rows MUST assert that the operation raises an `audit_immutable` SQLite
error.

A chain verification command (`spec validate --lane audit`) walks all rows in `requestedAt` order,
recomputes each `previousEntryDigest`, and reports the first broken link. Exit code 0 indicates an
intact chain; exit code 1 indicates tampering with a human-readable report.

Credentials (tokens, certificates, passwords) MUST NOT appear in any audit entry field. The
`command` field stores manifests only after credential-containing annotations have been redacted.

### Assistant remains read-only

The `cluster_intelligence` context does not receive any mutating tools in this release.
LLM-initiated mutations require a separate safety review covering prompt-injection resistance,
confirmation UX for agent-driven actions, and rollback strategies. That review is deferred to a
future ADR.

### Kubeconfig immutability preserved

Nothing in this ADR modifies the read-only treatment of kubeconfig files established in ADR-0003.
The application never writes, merges, or deletes kubeconfig entries. Kubernetes API credentials
remain in-memory only for the duration of outgoing requests.

### Consequences

- **Positive** — operators gain a full Kubernetes resource management surface inside a native macOS
  UI; audit trail satisfies enterprise compliance requirements; SSA field manager enables ownership
  traceability; double-confirm prevents accidental deletes.
- **Negative** — the confirmation modal adds friction to each operation; the diff fetch before apply
  adds one extra round-trip; the SQLite audit table grows over time and will need a retention
  policy.
- **Neutral** — the assistant constraint is an intentional deferral, not a permanent restriction;
  the boundary is enforced at the `MutationGuardPort` level so that adding assistant tools later
  requires only a policy update, not a structural change.

### Confirmation

- The Rego policy `contexts/resource_browser/policies/mutation_guard.rego` encodes the allowlist,
  confirmation freshness, double-confirm requirements, and the full verb set (apply, scale,
  scale-to-0, rollout-restart, delete, evict, force-delete, cordon, uncordon, finalizer-patch,
  image-change, rbac-mutation, label-patch, annotation-patch); a policy unit test suite achieves
  100% rule coverage.
- The `cluster_mutation_audit` table schema is validated by a CUE constraint in
  `contexts/resource_browser/schemas/mutation_audit_entry.cue`. The schema includes a `requestId`
  (UUIDv7) field; a test verifies that duplicate `requestId` submissions are rejected before
  dispatch.
- An integration test exercises a complete apply lifecycle: diff fetch, modal confirmation, SSA
  dispatch, audit entry persisted with `outcome=succeeded`.
- An integration test cancels a delete at the double-confirm modal and asserts that no API call was
  dispatched and the audit entry has `outcome=cancelled`.
- Integration tests for each `requiresDoubleConfirm: true` verb (delete, evict, force-delete,
  finalizer-patch, rbac-mutation) verify that the double-confirm modal requires the exact resource
  name to be typed before the action button activates, and that a mismatch leaves the button
  disabled.
- A unit test for the `evict` verb verifies that a `429` response from the API server is surfaced as
  `#EvictionBlocked` with the PDB name extracted from the response body.
- A unit test for the `force-delete` verb verifies that the query parameter `gracePeriodSeconds=0`
  is present on the DELETE request and that the audit entry carries `verb=force-delete`.
- A unit test for `cordon` and `uncordon` verifies that the correct `spec.unschedulable` patch value
  is sent and the `resourceVersion` from the live Node object is included in the request.
- A unit test for `rbac-mutation` verifies that the mutation is blocked by the policy if the
  operator has not completed the double-confirm flow, even if the API request is otherwise
  well-formed.
- A code search for `cluster_intelligence` returning any symbol whose name contains `mutate`,
  `apply`, `scale`, `delete`, `patch`, `restart`, `evict`, `cordon`, `drain`, or `finalize` returns
  zero results.

## Pros and cons of the options

### Option A — Full CRUD with explicit confirmation (chosen)

- **Pros** — complete operator value; audit trail covers all operations; SSA with field manager is
  the modern Kubernetes recommended practice; diff preview reduces surprises; double-confirm guards
  the most destructive path; assistant boundary is clean and extensible.
- **Cons** — more surface area to implement and test; confirmation modals add UX friction;
  force-ownership toggle requires careful copy to avoid misuse.

### Option B — Conservative write subset (apply and scale only)

- **Pros** — smaller implementation surface; delete risk is entirely avoided; easier to reason
  about.
- **Cons** — operators cannot delete resources from the UI, which is a core expectation of any
  Kubernetes manager; label and annotation patching covers a disproportionately large share of
  day-to-day operations and cannot be deferred indefinitely.

### Option C — Remain read-only

- **Pros** — zero mutation risk; no audit infrastructure needed; ADR-0003 unchanged.
- **Cons** — the `resource_browser` context provides read-only visibility only, which is
  insufficient for the MVP+ product goals stated in ADR-0006; operators would have to switch to
  `kubectl` for every write operation, defeating the purpose of a native manager.

## More information

- ADR-0003 — Credential layer remains read-only; this ADR narrows the "no cluster write" clause to
  the credential layer only.
- ADR-0005 — Bounded contexts overview; `resource_browser` is a first-class context.
- ADR-0006 — MVP+ scope defines the kinds and operations that `resource_browser` must support.
- ADR-0010 — `local_persistence` owns the SQLite pool; `cluster_mutation_audit` is a table within
  that pool.
- ADR-0011 — All async mutation dispatches follow the Swift Concurrency conventions (structured
  tasks, named actors, cancellation propagation).
- Kubernetes documentation on server-side apply and field managers: referenced via the
  `resource_browser` domain narrative.
