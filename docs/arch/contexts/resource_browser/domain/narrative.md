# Bounded Context — `resource_browser`

## Purpose

Own the complete model of "what Kubernetes resources are present in a
cluster, and how does an operator inspect and mutate them". This
context is the single source of truth for resource enumeration,
kind-catalogue management, YAML editing, mutation command construction,
mutation guard evaluation, and audit log persistence within K8sManager.

No other context lists or watches Kubernetes resources. No other context
constructs or dispatches mutation commands. No other context evaluates
the mutation guard policy. The `cluster_intelligence` assistant context
reads from this context's read models but MUST NOT hold a reference to
any port that can issue mutations.

## Ubiquitous language

- **Kind** — a Kubernetes resource type identified by its group,
  version, and kind name (GVK). The `resource_browser` context
  maintains a static catalogue of supported kinds supplemented by
  dynamically discovered CRD kinds.
- **Resource** — a single instance of a kind. Identified by the tuple
  (contextId, namespace, name, uid). Resources are always fetched live
  from the cluster; the context holds no durable cache of resource state
  beyond the current watch stream.
- **Watch** — a long-lived server-sent-events stream opened on a kind
  (optionally filtered by namespace). Watch events carry incremental
  deltas (ADDED, MODIFIED, DELETED) that the context applies to the
  in-memory read model for the current list view.
- **ResourceDescriptor** — an immutable value object that describes a
  kind: its GVK, plural name, namespaced flag, supported verbs, and
  supported subresources. The static catalogue is a map from GVK to
  #ResourceDescriptor. Dynamic CRDs are projected into #ResourceDescriptor
  values and merged into the catalogue at runtime.
- **ApplyOperation** — the act of submitting a full resource manifest
  to the Kubernetes API via server-side apply. Every ApplyOperation
  carries a field manager identifier (`com.archanjo.K8sManager`), a
  manifest YAML string, and a manifest digest.
- **MutationCommand** — an immutable value object representing the
  operator's intent to change cluster state. The sum type covers
  ApplyYAML, ScaleReplicas, RolloutRestart, DeleteResource, LabelPatch,
  and AnnotationPatch. Commands are constructed in the UI confirmation
  flow and evaluated by the MutationGuardPort before dispatch.
- **Confirmation** — the operator gesture that authorises a mutation.
  All mutations require at least a single-confirm modal. Delete
  operations require a double-confirm with exact name entry. The
  confirmation modal generates a #ConfirmationToken (UUIDv7) at display
  time. The token is embedded in the MutationCommand and verified by
  the mutation guard for freshness (maximum age 5 minutes).
- **AuditEntry** — an immutable record of a mutation attempt written
  to the `cluster_mutation_audit` SQLite table before the API call is
  dispatched. Carries the command, outcome, confirmation token,
  Kubernetes status code, and manifest digest. Never contains
  credential material.
- **FieldManager** — the identifier sent in every server-side apply
  request. Fixed value `com.archanjo.K8sManager`. Enables traceability
  of field ownership in the cluster.
- **ConflictResolution** — the strategy used when the API server
  returns HTTP 409 due to field ownership conflicts. Default strategy
  is to surface the conflict to the operator and block the apply.
  Force-ownership is an opt-in that re-issues the request with
  `force=true`. The opt-in requires an explicit operator gesture in the
  diff preview modal.
- **DiffPreview** — the structured three-way diff between the live
  server manifest and the proposed manifest, shown in the confirmation
  modal before every apply. Lines present only in the live manifest
  are shown as removals; lines present only in the proposed manifest
  are shown as additions; unchanged lines are collapsed.
- **KindCatalogue** — the in-memory registry of #ResourceDescriptor
  values. Static entries are loaded at application start from the list
  defined in ADR-0013. Dynamic entries are added (and removed) as
  CRDs are discovered or deleted on the connected cluster.

## Tactical roles

- **`ResourceBrowserService`** — DomainService. Orchestrates list,
  get, and watch operations against KubernetesApiPort. Holds the
  in-memory KindCatalogue. Emits #ResourceListItem and #ResourceDetail
  projections to the UI layer.
- **`MutationCommandFactory`** — DomainService. Constructs
  MutationCommand variants from UI input. Embeds the confirmation
  token and computes the manifest digest before handing the command
  to the guard.
- **`MutationDispatchService`** — DomainService. Receives an approved
  command from the guard, persists the audit entry, and invokes
  KubernetesApiPort. Handles retry-on-conflict (force-ownership flow)
  and maps API error responses to domain error types.
- **`KubernetesResourceRepositoryPort`** — Port (inbound). Adapter
  responsibility: translate Swift domain types to HTTP requests via
  `swiftkube/client 0.26` (static kinds) and `async-http-client`
  (dynamic CRDs and server-side apply PATCH).
- **`MutationGuardPort`** — Port (inbound). Adapter responsibility:
  evaluate a MutationCommand against the `mutation_guard.rego` policy
  and return either `allowed` or a set of denial reasons. Implemented
  by an in-process OPA evaluator.
- **`AuditLogPort`** — Port (outbound). Adapter responsibility: write
  a #MutationAuditEntry to the `cluster_mutation_audit` table via
  `PersistenceActor` (ADR-0011). Implemented by the
  `local_persistence` context adapter.
- **`WatchStreamCoordinator`** — DomainService (actor). Manages the
  lifecycle of watch streams opened against the cluster. Maintains a
  map of (GVK, namespace?) to active `AsyncThrowingStream`. Cancels
  streams when the operator switches kind or namespace. Reconnects on
  stream error with exponential back-off.

## Dependencies

- **Reads** `ClusterReadModel` from `cluster_connectivity` to obtain
  the active context's API server URL, auth info reference, and
  cluster UID. Does NOT parse kubeconfig itself.
- **Consumes** `KubernetesApiPort` from `cluster_connectivity` for
  outbound HTTP calls. The port is injected at startup; the domain
  core never imports SwiftkubeClient or async-http-client directly.
- **Persists** via `AuditLogPort` backed by `local_persistence`. The
  `cluster_mutation_audit` table schema is owned by
  `local_persistence`; the column mapping must match the CUE schema
  in `contexts/resource_browser/schemas/mutation_audit_entry.cue`.
- **Does not depend on** `context_navigation`, `app_shell`,
  `llm_provider`, `assistant_chat`, or `cluster_intelligence`. These
  contexts may consume read models from `resource_browser` but the
  dependency never flows the other way.

## Read models exposed to other contexts

- **`ResourceListReadModel`** — a paginated list of #ResourceListItem
  values for the current (kind, namespace) selection. Consumed by the
  `app_shell` search and by `cluster_intelligence` for assistant
  context about running workloads.
- **`ResourceDetailReadModel`** — a single #ResourceDetail value for
  the currently open resource. Consumed by `cluster_intelligence` for
  answering questions about a specific resource.
- **`AuditLogReadModel`** — a paginated, reverse-chronological view
  of #MutationAuditEntry rows. Consumed by `app_shell` for the audit
  history panel.

## Invariants

- The kind allowlist encoded in ADR-0013 and evaluated by the
  `mutation_guard.rego` policy is the authoritative source of which
  GVKs may be mutated. A mutation command whose `targetGVK.kind` is
  not in the allowlist is denied without an API call.
- Server-side apply is the default and only apply strategy. The
  application never sets `kubectl.kubernetes.io/last-applied-configuration`.
  Client-side apply is forbidden.
- Every mutation command must carry a non-empty confirmation token.
  The token must be at most 5 minutes old at evaluation time.
- Delete commands must carry `doubleConfirmed=true`. This field may
  only be set by the UI layer after the operator has typed the exact
  resource name into the confirmation text field.
- The `cluster_intelligence` assistant context does not hold a
  reference to `MutationGuardPort`, `MutationDispatchService`, or any
  port that can issue Kubernetes write operations. This invariant is
  enforced architecturally (the assistant context's dependency graph
  does not include these types) and is confirmed by a code search in CI.
- Audit entries are append-only. No code path in the application
  issues `UPDATE` or `DELETE` on `cluster_mutation_audit`.
- Credential material (tokens, certificates, Secret data values) MUST
  NOT appear in any audit entry field. The `MutationCommandFactory`
  redacts Secret data values before serialising the command.

## Out of scope

- `exec` into a container (deferred; requires pty-level UX and
  additional security review).
- Port-forward tunnels (deferred to a future milestone).
- Bulk select and bulk delete operations (deferred).
- Helm install, upgrade, and rollback (deferred to the
  `helm_management` bounded context, future ADR).
- Custom column configuration and advanced field-selector queries
  (deferred).
- LLM-initiated mutations via the `cluster_intelligence` assistant
  (deferred to a future ADR covering prompt-injection resistance and
  rollback strategies).
- Kubeconfig editing (explicitly out of scope per ADR-0003; not
  affected by ADR-0012).
