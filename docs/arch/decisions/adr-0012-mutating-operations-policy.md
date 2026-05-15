# ADR-0012 — Mutating operations policy for cluster resources

- Status — Proposed; supersedes the "no cluster write" restriction in ADR-0003
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — mutations, safety, ux, audit, server-side-apply, conflict-resolution

## Context and problem statement

ADR-0003 declared that K8sManager is read-only against Kubernetes
clusters. That restriction was appropriate for the MVP scope, which
covered connectivity and context switching only. ADR-0006 introduced
the `resource_browser` bounded context into the MVP+ roadmap. That
context is the natural home for resource editing, scaling, rollout
restarts, and delete operations.

The question is no longer whether the application should mutate clusters
at all — the product direction has settled that it should — but rather
under what conditions, with what safeguards, and with what audit
obligations mutations are permitted.

This ADR narrows the read-only restriction of ADR-0003 to the
credential layer (kubeconfig is still never written; cluster
credentials are still never persisted) and establishes a complete
safety policy for cluster resource mutations within the
`resource_browser` context.

The secondary question is whether the LLM assistant
(`cluster_intelligence`) should gain mutating tools. This ADR
explicitly defers that capability and keeps the assistant read-only
until a separate ADR is approved.

## Decision drivers

- **Explicit operator intent** — every mutation must originate from a
  deliberate UI gesture; no implicit, scheduled, or background mutations.
- **Reversibility awareness** — operators must understand what will
  change before it changes; YAML diff preview is mandatory for apply
  operations.
- **Double-confirm for irreversible operations** — delete is the
  clearest case; the operator must confirm twice and must type the
  resource name to proceed.
- **Field manager accountability** — every server-side apply (SSA)
  operation must carry a fixed, recognisable `fieldManager` identifier
  so that ownership conflicts are traceable to this application.
- **Audit trail** — every mutation attempt (succeeded, denied, failed,
  or cancelled) must be persisted to SQLite before the API call is
  dispatched, enabling forensic review.
- **Conflict resolution is opt-in** — the application defaults to
  standard SSA conflict detection; forcing ownership over conflicting
  fields is an explicit operator opt-in, not the default.
- **Assistant remains read-only** — the LLM assistant context
  (`cluster_intelligence`) does not receive mutating tools in this
  release cycle. Safety requirements for LLM-driven mutations are a
  separate decision.
- **Kubeconfig immutability preserved** — nothing in this ADR alters
  the read-only treatment of kubeconfig files and cluster credentials
  established in ADR-0003.

## Considered options

- **Option A** — Full CRUD with explicit confirmation (chosen).
- **Option B** — Conservative write subset (apply and scale only;
  no delete; no label/annotation patch).
- **Option C** — Remain read-only; defer all mutations to a future
  release.

## Decision outcome

Chosen option — **Option A**, because it delivers the full operator
value of a Kubernetes manager, the safety policy is sufficient to
prevent accidental mutations, and the audit log satisfies the
accountability requirement.

### Mutation scope

The `resource_browser` context is permitted to issue the following
classes of Kubernetes API mutations:

- **Apply** — server-side apply via `PATCH` with
  `Content-Type: application/apply-patch+yaml` and field manager
  `com.archanjo.K8sManager`. Supported for all kinds in the
  `resource_browser` allowlist.
- **Scale** — `PATCH` on the `/scale` subresource for
  `Deployment`, `StatefulSet`, and `ReplicaSet`. Represented as an
  `#ApplyYAML` command targeting the scale sub-resource, or as a
  dedicated `#ScaleReplicas` command.
- **Rollout restart** — `PATCH` on the `spec.template.metadata.annotations`
  field, injecting `kubectl.kubernetes.io/restartedAt` with an RFC3339
  timestamp. Supported for `Deployment`, `DaemonSet`, and `StatefulSet`.
- **Delete** — `DELETE` verb on namespaced and cluster-scoped resources.
  Subject to double-confirm and grace-period selection.
- **Label patch** — strategic merge patch on `metadata.labels` only.
  Represented as `#LabelPatch`.
- **Annotation patch** — strategic merge patch on
  `metadata.annotations` only. Represented as `#AnnotationPatch`.

### Confirmation requirements

Every mutation requires at least one layer of explicit operator
confirmation:

- **Single confirm** — a modal sheet presents the mutation summary
  (kind, name, namespace, verb) and a diff preview (for apply) before
  the API call is dispatched. The operator must press a labelled
  destructive-action button ("Apply", "Scale", "Restart"). Dismiss
  cancels with no API call made.
- **Double confirm for delete** — the delete modal presents the
  resource identity and propagation policy, then requires the operator
  to type the exact resource name into a text field before the
  "Delete" button becomes enabled. A second tap on the "Delete" button
  issues the API call.

### YAML diff preview

Before any `#ApplyYAML` operation is dispatched, the application
fetches the live server manifest (`GET` with
`Accept: application/yaml`), diffs it against the proposed manifest
using a structured three-way merge algorithm, and renders the diff
inline in the confirmation modal. Lines present only in the live
manifest are shown as removed; lines present only in the proposed
manifest are shown as added; unchanged lines are collapsed.

If the live manifest cannot be fetched (e.g., the resource does not
yet exist), the diff is shown as a pure addition.

### Server-side apply and field manager

All apply operations use server-side apply (SSA). The field manager
identifier is `com.archanjo.K8sManager`. The application never uses
client-side apply (`kubectl.kubernetes.io/last-applied-configuration`).

Default behaviour on conflict is to surface the conflicting field
paths to the operator and refuse to proceed. The operator may opt in
to force ownership via a labelled toggle ("Force ownership — take
over conflicting fields") in the diff preview modal. Force ownership
re-issues the same `PATCH` with `force=true`. A prominent warning
label accompanies the toggle.

### Audit log

Every mutation command, including cancellations, is written to the
`cluster_mutation_audit` SQLite table (owned by the
`local_persistence` context) before the API call is dispatched. The
schema is captured in
`contexts/resource_browser/schemas/mutation_audit_entry.cue`.

Mandatory fields:

- `id` — UUIDv7 generated at command construction time.
- `requestedAt` — RFC3339 timestamp of command construction.
- `kubernetesContextId` — UUIDv7 of the active cluster context.
- `command` — the serialised `#MutationCommand` sum type.
- `outcome` — one of `succeeded`, `denied`, `failed`, `cancelled`.
- `kubernetesStatusCode` — the HTTP status code returned by the
  API server, if an API call was made.
- `manifestDigest` — SHA-256 of the YAML sent in the request body,
  for apply operations.
- `confirmationToken` — the UUIDv7 generated in the confirmation
  modal, linking the audit entry to the operator gesture.

The audit table is append-only. Rows are never updated or deleted by
the application. A future ADR may introduce a retention policy.

Credentials (tokens, certificates, passwords) MUST NOT appear in any
audit entry field. The `command` field stores manifests only after
credential-containing annotations have been redacted.

### Assistant remains read-only

The `cluster_intelligence` context does not receive any mutating
tools in this release. LLM-initiated mutations require a separate
safety review covering prompt-injection resistance, confirmation UX
for agent-driven actions, and rollback strategies. That review is
deferred to a future ADR.

### Kubeconfig immutability preserved

Nothing in this ADR modifies the read-only treatment of kubeconfig
files established in ADR-0003. The application never writes, merges,
or deletes kubeconfig entries. Kubernetes API credentials remain
in-memory only for the duration of outgoing requests.

### Consequences

- **Positive** — operators gain a full Kubernetes resource management
  surface inside a native macOS UI; audit trail satisfies enterprise
  compliance requirements; SSA field manager enables ownership
  traceability; double-confirm prevents accidental deletes.
- **Negative** — the confirmation modal adds friction to each
  operation; the diff fetch before apply adds one extra round-trip;
  the SQLite audit table grows over time and will need a retention
  policy.
- **Neutral** — the assistant constraint is an intentional deferral,
  not a permanent restriction; the boundary is enforced at the
  `MutationGuardPort` level so that adding assistant tools later
  requires only a policy update, not a structural change.

### Confirmation

- The Rego policy `contexts/resource_browser/policies/mutation_guard.rego`
  encodes the allowlist, confirmation freshness, and double-confirm
  requirements; a policy unit test suite achieves 100% rule coverage.
- The `cluster_mutation_audit` table schema is validated by a CUE
  constraint in `contexts/resource_browser/schemas/mutation_audit_entry.cue`.
- An integration test exercises a complete apply lifecycle:
  diff fetch, modal confirmation, SSA dispatch, audit entry
  persisted with `outcome=succeeded`.
- An integration test cancels a delete at the double-confirm modal
  and asserts that no API call was dispatched and the audit entry
  has `outcome=cancelled`.
- A code search for `cluster_intelligence` returning any symbol whose
  name contains `mutate`, `apply`, `scale`, `delete`, `patch`, or
  `restart` returns zero results.

## Pros and cons of the options

### Option A — Full CRUD with explicit confirmation (chosen)

- **Pros** — complete operator value; audit trail covers all
  operations; SSA with field manager is the modern Kubernetes
  recommended practice; diff preview reduces surprises; double-confirm
  guards the most destructive path; assistant boundary is clean and
  extensible.
- **Cons** — more surface area to implement and test; confirmation
  modals add UX friction; force-ownership toggle requires careful
  copy to avoid misuse.

### Option B — Conservative write subset (apply and scale only)

- **Pros** — smaller implementation surface; delete risk is
  entirely avoided; easier to reason about.
- **Cons** — operators cannot delete resources from the UI, which
  is a core expectation of any Kubernetes manager; label and
  annotation patching covers a disproportionately large share of
  day-to-day operations and cannot be deferred indefinitely.

### Option C — Remain read-only

- **Pros** — zero mutation risk; no audit infrastructure needed;
  ADR-0003 unchanged.
- **Cons** — the `resource_browser` context provides read-only
  visibility only, which is insufficient for the MVP+ product
  goals stated in ADR-0006; operators would have to switch to
  `kubectl` for every write operation, defeating the purpose of a
  native manager.

## More information

- ADR-0003 — Credential layer remains read-only; this ADR narrows
  the "no cluster write" clause to the credential layer only.
- ADR-0005 — Bounded contexts overview; `resource_browser` is a
  first-class context.
- ADR-0006 — MVP+ scope defines the kinds and operations that
  `resource_browser` must support.
- ADR-0010 — `local_persistence` owns the SQLite pool;
  `cluster_mutation_audit` is a table within that pool.
- ADR-0011 — All async mutation dispatches follow the Swift
  Concurrency conventions (structured tasks, named actors,
  cancellation propagation).
- Kubernetes documentation on server-side apply and field managers:
  referenced via the `resource_browser` domain narrative.
