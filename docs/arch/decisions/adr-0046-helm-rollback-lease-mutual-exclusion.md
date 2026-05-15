# ADR-0046 — Helm rollback Lease-based mutual exclusion

- Status — Accepted (ratified 2026-05-15)
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — helm, rollback, concurrency, lease, helm_management

## Context and problem statement

ADR-0015 introduces phased native Helm support. Phase 1 includes rollback by writing a new revision
Secret labelled `owner=helm` and applying the target revision's manifests via server-side apply. If
two operators (or two app instances launched back-to-back) initiate a rollback for the same release
at the same time, the second writer can overwrite the first writer's new revision Secret, leaving
the release chain in a corrupted state with two "current" revisions or with the wrong manifests
applied. The Gherkin scenario
`docs/arch/contexts/helm_management/features/lifecycle/concurrent-rollback-with-lease.feature`
exercises this case but no ADR defines the mutual exclusion mechanism.

## Decision drivers

- **Idempotent rollback** — the same rollback request must produce the same final state regardless
  of how many times it is issued in parallel.
- **Server-side primitive** — rollback is a cluster operation; the lock must live in the cluster,
  not in the desktop app, so that rollback intent is observable from any operator.
- **Bounded holding time** — leases must auto-expire so that a crashed app does not block rollback
  indefinitely.
- **Standard Kubernetes mechanism** — re-use the existing `coordination.k8s.io/v1/Lease` primitive
  (the same used by kube-scheduler, kube-controller-manager, and other leader-election consumers).

## Considered options

1. **No mutex** — rejected. Race surface as above.
2. **Client-side mutex (in-memory)** — rejected. Does not cover the "two app instances" or "two
   operators on same cluster" case.
3. **Annotation-based mutex on the release Secret** — rejected. Annotations are not atomic and
   Kubernetes does not provide a compare-and-swap primitive for them in the way Lease provides
   `resourceVersion`-based optimistic concurrency for the lease spec.
4. **`coordination.k8s.io/v1/Lease` per release** — chosen.

## Pros and cons of the options

### Option 1 — No mutex

- Bad, because two concurrent rollbacks for the same release can each write a "current" revision
  Secret, leaving the release history chain with two active revisions or incorrect manifests
  applied.

### Option 2 — Client-side mutex (in-memory)

- Bad, because an in-memory lock within one application instance cannot coordinate with a second app
  instance or a second operator on the same cluster; the race surface remains fully open for
  concurrent operators.

### Option 3 — Annotation-based mutex on the release Secret

- Bad, because Kubernetes does not provide a compare-and-swap primitive for annotations; two
  concurrent writers using the same annotation key cannot safely detect each other without a
  server-side atomic gate.

### Option 4 — `coordination.k8s.io/v1/Lease` per release (chosen)

- Good, because the Lease object provides `resourceVersion`-based optimistic concurrency natively;
  only one writer can successfully update a Lease with a given `resourceVersion`, preventing
  concurrent acquisition by construction.
- Good, because `leaseDurationSeconds: 60` auto-expires the lock if the acquiring process crashes,
  eliminating indefinite blocking without requiring a separate cleanup process.
- Good, because the Lease is visible to cluster administrators for the duration of rollback and
  auditable from outside the application.
- Bad, because operators without `create/get/patch/delete` on `leases` in the release namespace
  cannot perform rollback; clusters with restrictive RBAC must grant this access explicitly.

## Decision outcome

- **Lease object**:
  - API group: `coordination.k8s.io/v1`.
  - Kind: `Lease`.
  - Namespace: the same namespace as the Helm release Secret.
  - Name: `k8smanager-helm-rollback-<release-name>` (kebab-case truncated to 63 characters per RFC
    1123).
  - Spec:
    - `holderIdentity`: `k8smanager-<instanceId>-<operatorEmail>` where `instanceId` is the
      per-launch UUIDv7 (ADR-0042) and `operatorEmail` is the local macOS user (best-effort
      identifier).
    - `leaseDurationSeconds`: 60.
    - `acquireTime`: RFC 3339 set at acquisition.
    - `renewTime`: RFC 3339 refreshed every 20 seconds while rollback is in progress.
- **Acquisition protocol**:
  1. `GET` the lease. If not found, `POST` it with the operator's `holderIdentity` and current time;
     on 409 Conflict, restart from step 1.
  2. If found and `renewTime + leaseDurationSeconds < now`, the lease is stale; `PUT` it with our
     `holderIdentity` and current time using `resourceVersion` optimistic concurrency; on 409
     Conflict, restart from step 1.
  3. If found and not stale and `holderIdentity != ours`, the rollback is aborted with a
     `RollbackContention` audit entry naming the current holder.
- **Renewal**: while the rollback is in progress, a background task refreshes `renewTime` every 20
  seconds. If the renewal fails (lease was stolen by a stale-cleanup race), the rollback aborts with
  a `RollbackContention` audit entry; no new Secret is written.
- **Release**: on rollback completion (success or failure), the lease is `DELETE`d. If deletion
  fails, the lease will auto-expire after `leaseDurationSeconds`.
- **Operator UX**: when contention is detected, the operator sees a message naming the conflicting
  `holderIdentity` and a "Try again" affordance that retries acquisition after 5 seconds.
- **No queue**: rejected rollbacks are not queued; the operator re-initiates manually.

### Consequences

- **Positive** — race-free rollback against concurrent operators or app instances; standard
  Kubernetes primitive with predictable behaviour; auto-expiry on crashed app.
- **Negative** — adds a Kubernetes API dependency for rollback (cluster must permit
  `coordination.k8s.io/v1` access); operators without `create/get/patch/delete` on `leases` in the
  release namespace cannot rollback.
- **Neutral** — the Lease object remains visible to cluster admins for the duration of rollback;
  auditable from outside the app.

### Confirmation

- Integration test: two app instances issue rollback for the same release simultaneously; exactly
  one writes the new revision Secret; the other receives `RollbackContention`.
- Stale-lease test: kill the holding app process; another instance detects expired lease after
  `leaseDurationSeconds + jitter` and acquires successfully.
- Audit log: each `RollbackContention` writes a single audit entry naming the conflicting
  `holderIdentity`.
- Lease cleanup: on successful rollback, the Lease object is deleted; verified via
  `kubectl get leases -n <namespace>`.

## More information

- ADR-0015 — Native Helm in phased delivery (Phase 1 rollback contract).
- ADR-0012 — Mutating operations policy (audit log writer).
- ADR-0025 — Per-cluster isolation (per-cluster `coordination.k8s.io` client binding).
- ADR-0042 — Single-instance enforcement (`instanceId` UUIDv7 source).
- Kubernetes API reference: `coordination.k8s.io/v1/Lease`.
- Gherkin scenario:
  `docs/arch/contexts/helm_management/features/lifecycle/concurrent-rollback-with-lease.feature`.
