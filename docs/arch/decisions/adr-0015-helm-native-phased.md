# ADR-0015 — Helm native phased implementation

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — helm, native-swift, phased, oci, ssa, rollback, template-engine

## Context and problem statement

K8sManager's stated goal is to manage Kubernetes clusters entirely through the Kubernetes REST API,
with no subprocess invocations of third-party CLIs. ADR-0006 introduced the MVP+ scope and listed
Helm release management as a desired capability. ADR-0012 established the mutation policy that all
cluster-writing operations must follow.

Helm 3 is the dominant release-management tool for Kubernetes workloads. An operator using
K8sManager without Helm awareness must leave the application and switch to the `helm` CLI for any
inspection or lifecycle operation. This breaks the goal of a single pane of glass for cluster
management.

The question is how to implement Helm awareness natively in Swift 6 without spawning a `helm`
subprocess. Helm has two distinct capability surfaces:

1. Reading existing release state — listing releases, inspecting manifests and values, viewing
   history, performing rollback. This surface is entirely implementable by reading Kubernetes
   Secrets of type `helm.sh/release.v1` that Helm's default storage driver (`secret`) writes to the
   cluster.

2. Computing new release state — template rendering, install, upgrade, lint, dependency resolution,
   OCI and HTTP chart pull. This surface requires a fully-functional Helm template engine, which is
   Go's `text/template` plus the Sprig function library (approximately 19,000 to 29,000 lines of Go
   that do not translate mechanically to Swift).

A second architectural question concerns rollback. Rollback in Helm creates a new revision by
re-applying the manifests from a previous revision. Under the read-only surface it is not necessary
to re-render anything — the stored manifest YAML from the target revision is available in the Secret
and can be re-applied via Server-Side Apply. This makes rollback achievable in Phase 1 without the
template engine.

A third question concerns strategic merge patch (3-way merge). The Helm CLI uses `strategicpatch`
(from `k8s.io/apimachinery`) to compute 3-way merges between the last-applied configuration, the
current live state, and the proposed new state. Porting `strategicpatch` to Swift is not
economically justified and has no maintained Swift equivalent. Helm 3.13 introduced Server-Side
Apply (SSA) as an opt-in apply strategy, delegating merge logic to the Kubernetes API server. This
is the preferred path for K8sManager.

A fourth question concerns alternative storage drivers. Helm supports `HELM_DRIVER=configmap`,
`HELM_DRIVER=sql`, and `HELM_DRIVER=memory`. Clusters where the operator has configured a
non-default driver will not have `helm.sh/release.v1` Secrets. The MVP+ scope must degrade
gracefully.

## Decision drivers

- **No subprocess** — spawning `helm` is explicitly ruled out by the product direction. All cluster
  interaction must go through the Kubernetes REST API.
- **Read-first value delivery** — the majority of operator interactions with Helm are read-only
  (what is deployed, what version, what values). Delivering these without the template engine
  unblocks 80 percent of the use-case immediately.
- **Rollback is high-value and achievable** — rollback to a stored revision does not require
  re-rendering. It is a mutating operation under ADR-0012 and can be implemented in Phase 1.
- **Template engine scope is bounded** — a complete Swift port of `text/template` plus Sprig is
  estimated at 19,000 to 29,000 lines of original Swift code requiring 13 to 20 months of dedicated
  engineering. This is a Phase 2 item.
- **Strategic merge patch is never ported** — Server-Side Apply from the Kubernetes API server is a
  better architectural choice. It is maintained by the Kubernetes project, handles all
  resource-specific merge strategies automatically, and removes the need for K8sManager to carry
  merge logic.
- **OCI chart pull is scoped to Phase 2** — the `apple/swift-container-plugin` provides OCI artifact
  pull capability and is the chosen implementation path for pulling charts from OCI registries in
  Phase 2.
- **Graceful degradation for non-default drivers** — operators using `configmap` or `sql` drivers
  see a clear informational message rather than a crash or silent empty list.

## Considered options

### Option A — Full native big-bang

Implement Phases 1 and 2 together: native template engine, install, upgrade, rollback, lint, OCI
pull, HTTP repo, all in a single milestone.

Reasons for rejection:

- The template engine is the dominant cost (19,000 to 29,000 lines of Swift, 13 to 20 months). There
  is no existing Swift port of Go's `text/template` or of Sprig.
- Stencil (Swift templating library) uses Jinja2-style `{{ }}` syntax and does not implement Go
  template semantics (range, with, define, block, template, pipeline chaining). Not a viable
  substitute.
- GRMustache covers Mustache syntax only. Not a viable substitute.
- `mattt/JSONSchema` provides JSON Schema validation (Tier B quality, partially maintained) and can
  validate `values.schema.json` but does not contribute to template rendering.
- Delaying all Helm value to a single large milestone creates a long gap with no deliverable
  increment for operators.
- Strategic merge patch (3-way) is an additional dependency on top of the template engine with no
  viable Swift port and no justification given that SSA is available.

### Option B — Subprocess helm delegation

Detect `helm` binary on PATH, spawn subprocesses for all operations, parse output and error streams.

Reasons for rejection:

- Directly contradicts the product direction of no subprocess invocations.
- Application behaviour becomes dependent on the operator's locally installed `helm` version
  (semantic drift between Helm 2 and Helm 3, Helm 3.12 vs 3.15 flag changes).
- macOS Hardened Runtime and App Sandbox restrictions complicate subprocess PATH resolution and may
  block execution in a notarised build.
- Parsing unstructured `helm` output or JSON flags adds fragile coupling with no type safety.

### Option C — Hybrid phased (chosen)

Implement Phase 1 immediately by reading `helm.sh/release.v1` Secrets directly via the Kubernetes
API. Implement rollback via Server-Side Apply of stored manifests. Implement Phase 2 (template
engine, install, upgrade, OCI pull) as a subsequent milestone after Phase 1 ships.

This option is chosen.

## Decision outcome

### Phase 1 — MVP+ (implemented now)

Phase 1 covers the complete read surface plus rollback.

**Secret decoding.** Helm 3 stores release state in Kubernetes Secrets of type `helm.sh/release.v1`
with label `owner=helm`. Each Secret is named `sh.helm.release.v1.<release-name>.v<revision>`. The
`data["release"]` field contains a base64-encoded, gzip-compressed JSON blob conforming to the Helm
`release.Release` Go struct. Decoding procedure:

1. Base64-decode `data["release"]` using Foundation `Data(base64Encoded:)`.
2. Gunzip the decoded bytes using `Foundation.Compression` framework (algorithm `.zlib` with gzip
   framing; or `SWCompression` as an alternative dependency for explicit gzip format support).
3. JSON-decode the resulting bytes into the `HelmReleasePayload` Swift struct using
   `Foundation.JSONDecoder`.

The decoded struct contains: `chart` (Chart metadata, default values, templates list, CRD manifests,
files), `config` (user-supplied values as a JSON map), `manifest` (the rendered YAML string that was
applied to the cluster), `hooks` (list of Hook objects with manifest YAML, events, delete policy,
and weight), `info` (first-deployed, last-deployed, deleted, description, status, notes), `name`,
`namespace`, `version` (revision integer), `labels`.

**Release decoder invariants.** Before materialising a `#Release` aggregate from a decoded Secret,
the decoder applies the `release_decoder_invariants` Rego policy (see
`contexts/helm_management/policies/release_decoder_invariants.rego`). Invariants include: Secret
type must be `helm.sh/release.v1`; label `owner` must equal `helm`; `data["release"]` must be
present; gunzip must succeed; the rendered manifest YAML must not contain PEM-encoded certificates
(defence in depth — charts that embed credential material are rejected rather than displayed to the
operator).

**Grouping revisions.** Multiple Secrets for the same `(name, namespace)` tuple represent the
revision history of a single logical release. The `helm_management` context groups these by the
release name and namespace extracted from the JSON payload (not from the Secret name, to handle edge
cases). The latest revision is the one with the highest `version` integer and status `deployed` (or
the most recent non-superseded status if no deployed revision exists).

**Status mapping.** The Helm status enum maps to: `deployed`, `uninstalled`, `superseded`, `failed`,
`pending-install`, `pending-upgrade`, `pending-rollback`. Revisions with status `superseded` are
hidden by default in the list view but accessible through the history view.

**Rollback.** The rollback operation creates a new revision Secret containing the manifests from the
target revision, applies the manifests to the cluster via Server-Side Apply (field manager
`com.archanjo.K8sManager`), and sets the new revision's status to `deployed` while marking the
previous current revision as `superseded`. Rollback is a mutating operation subject to ADR-0012:
operator must confirm via a double-confirm modal; an audit entry is written before the API call; the
command is typed `#RollbackTo`.

**Rollback edge cases.**

Missing CRDs in target revision: if the target revision's stored manifest YAML contains resources
whose API group/version/kind is not present in the cluster at rollback time (for example, CRDs that
were installed by the chart but have since been deleted), the SSA apply will fail with a
`404 Not Found` or `422 Unprocessable Entity` from the API server. When this occurs, no resource
from the target manifest is applied (the failure is detected on the first SSA request before any
partial state is written), the rollback is aborted, an audit entry is written with `outcome=failed`
and `detail=crd_missing`, and the new revision Secret is NOT written to the cluster. The current
deployed revision remains unchanged. The UI surfaces a `#RollbackAborted` event with a
human-readable explanation listing the missing kinds.

Concurrent rollback prevention: before writing the new revision Secret, the adapter must acquire a
Kubernetes `Lease` object of kind `coordination.k8s.io/v1` named
`k8smanager-helm-rollback-<release-name>` in the same namespace as the release. The Lease
`spec.leaseDurationSeconds` is set to 60. The adapter sets `spec.holderIdentity` to the
application's instance UUID (stable for the application lifetime, stored in memory). If the Lease
already exists and its `spec.holderIdentity` differs from the application's instance UUID, and its
`spec.renewTime` is within the past 60 seconds, the rollback is refused with `#RollbackConflict`. If
the Lease is expired (renewTime older than 60 seconds), the adapter overwrites it via an SSA patch.
The Lease is released (deleted) after the rollback completes (whether success or failure). On
application quit or task cancellation, any held Lease is deleted as part of the shutdown sequence.

Resource diff before applying: before issuing the SSA requests, the adapter fetches the live
server-side manifest for each resource in the target revision using `GET` with
`Accept: application/yaml`. It computes a three-way diff between the currently-deployed revision's
manifest, the live cluster state, and the target revision's manifest. The diff is presented to the
operator in the double-confirm modal under a "Changes" section, showing added, removed, and modified
resources. This allows the operator to understand what will change before confirming. If a live
resource cannot be fetched (e.g., it does not exist), that resource is shown as a pure addition in
the diff.

Half-applied recovery: the SSA approach issues one PATCH request per resource in the manifest,
sequentially. If any PATCH fails after one or more earlier PATCHes have succeeded, the rollback has
partially applied. In this case:

- The new revision Secret is NOT written to the cluster.
- The current revision's status is NOT changed to `superseded`.
- An audit entry is written with `outcome=failed` and `detail=partial_apply` listing the resources
  that succeeded and the resource that failed.
- The UI surfaces a `#RollbackPartialFailure` event with the list of applied and failed resources,
  and a recommendation to inspect cluster state manually.
- The operator may retry the rollback; the retry begins from the full manifest (not from the failed
  resource onward), because SSA is idempotent for already-applied resources.

**Storage driver degradation.** The application detects the absence of `helm.sh/release.v1` Secrets
as a possible signal that a non-default driver is in use. When no Helm Secrets are found in a
namespace that has Helm chart annotations visible on other resources (e.g.,
`app.kubernetes.io/managed-by=Helm` on Deployments), the UI displays a degradation banner: "Helm
releases not visible — the cluster may be using a non-secret Helm driver (configmap or sql). Manual
inspection via the Resource Browser is available."

**OCI registry (Phase 1 read-only).** Phase 1 does not pull charts from OCI registries. The chart
metadata embedded in the release Secret is sufficient for display purposes.

**HTTP repo legacy (Phase 1 read-only).** Phase 1 does not fetch chart archives from HTTP
repositories. The chart metadata embedded in the release Secret is sufficient for display purposes.

### Phase 2 — Post-MVP+ roadmap

Phase 2 scope includes:

- Native Swift port of Go's `text/template` package. Estimated 6,000 to 10,000 lines of Swift
  covering: template parsing (text nodes, action nodes, pipeline nodes, if/else, range, with,
  define, block, template, call nodes), execution engine (dot context, variable scope, function
  dispatch), and the built-in function set.
- Native Swift port of Sprig (approximately 100 template functions spanning string manipulation,
  math, date/time, encoding, hashing, cryptography, networking, UUID generation, OS environment).
  Estimated 13,000 to 19,000 lines of Swift. The cryptographic subset (PBKDF2, bcrypt, genCA,
  genSelfSignedCert) uses CryptoKit and Security.framework equivalents.
- `helm install` — renders chart templates, creates revision 1 Secret, applies rendered manifests
  via SSA.
- `helm upgrade` — renders chart templates against the new chart version and user-supplied values,
  creates a new revision Secret, applies via SSA.
- `helm template` — renders chart templates to stdout without applying.
- `helm lint` — validates chart structure, schema-validates values using `mattt/JSONSchema` for
  `values.schema.json`, checks for required fields.
- OCI chart pull via `apple/swift-container-plugin` — fetches chart archives with media type
  `application/vnd.cncf.helm.chart.content.v1.tar+gzip` from OCI-compliant registries.
  Authentication uses the macOS Keychain credential store.
- HTTP repo support — parses `index.yaml` from Helm HTTP chart repositories, downloads chart
  archives, verifies provenance signatures (`raymccrae/swift-jsonpatch` is not relevant here;
  provenance uses PGP via SwiftNIO, or delegated to an external pgp binary as a last resort).
- Repository credential management — stores OCI and HTTP repo credentials in the macOS Keychain via
  the `local_persistence` context.
- `helm dependency update` — resolves `Chart.yaml` dependencies, pulls sub-charts from their
  configured sources.

Phase 2 strategic merge replacement: Server-Side Apply replaces `strategicpatch` entirely.
K8sManager will never port `strategicpatch` (approximately 4,000 lines of Go with complex merge-key
annotation parsing). Helm 3.13+ `--server-side` flag confirms that SSA is a production-ready apply
strategy for Helm-managed resources.

Phase 2 timeline estimate: 13 to 20 months of dedicated engineering from the date this ADR is
accepted. No Phase 2 work is scheduled in the current planning cycle.

## Consequences

### Positive

- Phase 1 delivers high-value read and rollback capabilities without the template engine investment.
- The Secret-reading path requires no new binary dependencies — Foundation, Compression, and
  JSONDecoder are already available.
- SSA for rollback is cleaner than strategic merge patch; the Kubernetes API server handles field
  ownership and merge semantics correctly for all resource types including StatefulSet pod
  templates.
- The phased split creates a natural milestone boundary that can be shipped, demonstrated, and
  user-tested before Phase 2 begins.
- Rejecting subprocess delegation keeps the Hardened Runtime and App Sandbox posture clean.

### Negative

- Phase 1 cannot render templates or install new charts. Operators must continue to use the `helm`
  CLI for install and upgrade during the Phase 1 window.
- The template engine port in Phase 2 is a large, high-risk engineering effort. Any incomplete
  implementation of Go template semantics or Sprig functions will produce incorrect rendered
  manifests, which could cause unexpected cluster mutations.
- SWCompression is an optional dependency for explicit gzip support. If Foundation Compression
  framework's gzip handling proves insufficient (e.g., for multi-member gzip streams), SWCompression
  must be added to the Swift Package manifest.
- `raymccrae/swift-jsonpatch` provides only partial RFC 6902 JSON Patch support. It is not usable
  for strategic merge patch simulation. This is not a problem for Phase 1 (no merge logic needed)
  but must be re-evaluated if Phase 2 requires client-side patch preview.

### Neutral

- The `mattt/JSONSchema` library is Tier B quality (partially maintained, gaps in draft-2019-09
  keyword coverage). It is adequate for `values.schema.json` validation in Phase 2 but should be
  monitored for maintenance status.
- The `apple/swift-container-plugin` OCI implementation is the canonical Swift path for OCI artifact
  pull. Its API surface should be reviewed at Phase 2 kickoff to verify it supports the Helm chart
  media type.

## More information

- Supersedes none. Extends ADR-0006 (MVP+ scope expanded).
- Relates to ADR-0012 (mutating operations policy) — rollback is subject to double-confirm and audit
  requirements therein.
- Relates to ADR-0013 (resource browser scope) — rollback uses the same SSA apply pipeline
  introduced in ADR-0012.
- Helm Secret format reference —
  <https://github.com/helm/helm/blob/main/pkg/storage/driver/secrets.go>
- Helm 3.13 SSA release notes — <https://github.com/helm/helm/releases/tag/v3.13.0>
