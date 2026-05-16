# ADR-0060 — Resource list export (CSV and YAML)

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0050 (resource navigation taxonomy), ADR-0030 (integrated editor),
  ADR-0061 (per-row resource action menu uniform shape)
- Tags — export, csv, yaml, resource-browser, list-view

## Context and problem statement

The reference recording (Lens × Mirantis Prism AI, item R24 in the gap analysis) shows two
distinct export affordances in every resource list view:

1. A download icon placed directly next to the item-count badge at the top of the list. Activating
   it exports the currently visible (filtered, sorted) list as a CSV file.
2. A `Save YAML` action inside the per-row 3-dot context menu (R25 / ADR-0061) that writes the
   full Kubernetes object manifest for a single row to a YAML file.

K8S-Manager currently has neither affordance. Operators who need to audit a list, paste it into
an incident ticket, or archive a snapshot of live cluster state must either copy values manually
from the UI or fall back to `kubectl get -o json` outside the application.

Two concrete operator workflows drive this requirement:

- **Audit workflow** — a platform engineer needs to export all Pods in a namespace as a
  spreadsheet attachment for an incident post-mortem. A CSV with the visible columns (already
  filtered to the relevant namespace and search query) is the right artefact.
- **Paste-into-ticket workflow** — an SRE debugging an issue pastes a Deployment YAML into a
  Slack thread or Jira comment. The YAML must be a well-formed Kubernetes manifest, not a raw
  API response, and sensitive fields must not leak inadvertently.

## Decision drivers

- **Operator audit needs** — a plain-text, spreadsheet-friendly format (CSV) is the smallest
  useful artefact for list-level exports.
- **Paste-into-ticket workflows** — full Kubernetes YAML per resource is the canonical artefact
  for sharing a single resource spec in a support context.
- **No information leak through naive serialisation** — Secrets carry sensitive `data` values.
  Exporting raw Secret YAML without an explicit user opt-in would silently exfiltrate credentials.
  Redaction must be the default.
- **Audit trail** — every export operation must produce a signed audit log entry consistent with
  the ADR-0047 HMAC keychain chain.
- **Minimal surface** — CSV for lists; YAML for individual resources. No JSON list export, no
  binary formats. Each format serves a distinct use case; mixing them into a single modal adds
  complexity without matching operator mental models.

## Considered options

- **Option A — CSV export only.** Export the visible list to CSV; omit per-row YAML export.
  Simple to implement; covers the audit and paste-into-spreadsheet workflow. Does not cover the
  paste-into-ticket YAML workflow. Operators still need `kubectl get -o yaml` outside the app.

- **Option B — YAML export only.** Export the full object YAML per row; omit the list-level CSV
  download. Covers the paste-into-ticket workflow. Does not cover tabular audit workflows.
  Exporting an entire list as multi-document YAML is unwieldy in a spreadsheet context.

- **Option C — Both: CSV for list, YAML for single resource.** A download icon next to the item
  count triggers CSV list export; a `Save YAML` action in the per-row 3-dot menu triggers
  single-resource YAML export. Each format addresses its canonical use case without ambiguity.

## Decision outcome

**Chosen option — Option C**, because each format addresses a distinct operator use case that the
other cannot cover adequately. The CSV download and the per-row YAML action are independent entry
points; they share the audit log contract but otherwise have non-overlapping codepaths.

### CSV export contract

#### Entry point

A download icon (SF Symbol `arrow.down.circle`) is placed immediately to the right of the item
count badge in the list toolbar. It is always visible when the list contains at least one item. It
is hidden when the list is empty or still loading. A tooltip `Export list as CSV` appears on hover.

Activating the icon presents an `NSSavePanel` pre-populated with the filename template:

```
<Kind>-<ClusterDisplayName>-<ISO8601Timestamp>.csv
```

Example: `Pod-prod-aks-2026-05-16T14-32-07Z.csv`

The timestamp uses the format `YYYY-MM-DDTHH-MM-SSZ` (colons replaced with hyphens for
filesystem compatibility). The proposed directory defaults to `~/Downloads`.

#### Column subset per kind family

The CSV export writes only a curated subset of columns — not every field the Kubernetes API
returns. The column selection is fixed per kind family and is capped at 12 columns. The goal is a
spreadsheet that a human can read without reformatting.

Column definitions per kind family:

**Nodes:**
`name`, `kubernetes-version`, `age`, `roles`, `conditions`, `internal-ip`

**Pods:**
`name`, `namespace`, `status`, `ready`, `restarts`, `node`, `age`

**Deployments / StatefulSets / DaemonSets / ReplicaSets:**
`name`, `namespace`, `ready`, `up-to-date`, `available`, `age`

**Jobs / CronJobs:**
`name`, `namespace`, `completions`, `duration`, `age`

**ConfigMaps:**
`name`, `namespace`, `keys`, `age`

**Secrets:**
`name`, `namespace`, `type`, `keys`, `age`
(Secret `data` values are never written to CSV regardless of redaction preference.)

**Services:**
`name`, `namespace`, `type`, `cluster-ip`, `external-ip`, `ports`, `age`

**Ingresses:**
`name`, `namespace`, `class`, `hosts`, `address`, `ports`, `age`

**PersistentVolumes:**
`name`, `capacity`, `access-modes`, `reclaim-policy`, `status`, `claim`, `storage-class`, `age`

**PersistentVolumeClaims:**
`name`, `namespace`, `status`, `volume`, `capacity`, `access-modes`, `storage-class`, `age`

**Namespaces / Events / Custom Resources:**
`name`, `status`, `age` (minimal baseline; custom resource exports include the three columns
common to all and skip CRD-specific fields that would require per-GVK schema knowledge at
export time).

**Roles / RoleBindings / ClusterRoles / ClusterRoleBindings:**
`name`, `namespace`, `age`

The exported rows reflect the currently visible list — meaning the operator's active namespace
filter (ADR-0053), search query, and sort order are all respected. Rows are serialised in the
order they appear in the UI at the moment of export trigger.

#### CSV format

- Encoding: UTF-8.
- Delimiter: comma (`,`).
- Quoting: RFC 4180. Fields containing commas, double-quotes, or newlines are enclosed in double
  quotes. Embedded double-quote characters are escaped as `""`.
- Line endings: CRLF (`\r\n`) as mandated by RFC 4180 and expected by Microsoft Excel on macOS.
- BOM: optional. The `NSSavePanel` sheet includes a checkbox `Add BOM for Excel compatibility`
  (unchecked by default). When checked, the file is prefixed with the UTF-8 BOM (`EF BB BF`).
- Header row: always present as the first row. Column names match the lowercase-hyphenated
  identifiers listed in the column subset tables above.
- Multi-value fields (e.g. `conditions`, `roles`, `ports`) are serialised as a semicolon-separated
  list within a single quoted CSV field.
- Empty / unknown values are written as an empty string (two adjacent commas or `,"",`).

#### Export behaviour under active filters

The CSV export captures exactly what is visible in the list at the time of activation:

- If a namespace filter is active, only resources in that namespace are exported.
- If a search query is active, only matching rows are exported.
- If a sort order is active, the export preserves that order.
- The item count badge already reflects the filtered row count; the CSV row count matches it.

### YAML export per row

#### Entry point

A `Save YAML` menu item appears in the per-row 3-dot context menu, consistent with ADR-0061's
canonical action menu shape. Activating it:

1. Fetches the current live manifest for the resource via `KubernetesApiPort` (`GET` with
   `pretty=true`). The export uses a fresh fetch, not the cached watch-stream value, to ensure
   the exported YAML reflects the server's current state.
2. If `kind == Secret`, applies the redaction policy (see below) before presenting the
   `NSSavePanel`.
3. Presents an `NSSavePanel` pre-populated with the filename template:

```
<Kind>-<Namespace>-<Name>-<ISO8601Timestamp>.yaml
```

Example: `Deployment-default-my-api-2026-05-16T14-32-07Z.yaml`

For cluster-scoped resources the `<Namespace>-` segment is omitted:

```
Node-worker-01-2026-05-16T14-32-07Z.yaml
```

4. On file selection, writes the manifest via `FileManager` and records an audit log entry.

#### YAML serialisation

The manifest is written as-is from the Kubernetes API response, parsed by the `swiftkube` adapter
and re-serialised via `Yams` (ADR-0019). Key ordering follows the server response; no
alphabetical re-sort is applied (the operator receives what the API server holds). The YAML
document begins with `---` to make multi-document concatenation safe.

### Secret redaction rules

When the kind being exported is `Secret`, the following policy applies:

- The redaction decision dialog is presented before the `NSSavePanel`.
- The dialog body: "This resource is a Secret. Its data values will be replaced with hash
  placeholders to prevent credential exposure. Check the box below to export unredacted values."
- A checkbox `Export unredacted Secret data` is present and unchecked by default.
- When the checkbox remains unchecked (default): each value in `data` is replaced with a
  SHA-256 hash placeholder of the form `[redacted:sha256:<first8hexchars>]`. The hash is
  computed over the raw base64-decoded bytes so identical secrets produce identical placeholders
  across exports.
- When the checkbox is checked (operator opt-in): the full `data` map is written as received
  from the API, base64-encoded as Kubernetes specifies.
- The `stringData` field, if present, is always redacted (replaced with empty map) regardless of
  the operator's choice, because `stringData` values are plaintext by definition.
- The audit log entry (see below) records `redacted: true` or `redacted: false` accordingly.
- Redaction policy for other sensitive kinds (e.g. `ServiceAccount` tokens, `dockerconfigjson`
  interpretation) is deferred to ADR-0063.

### Filename templates

Summary of filename patterns:

- CSV list export: `<Kind>-<ClusterDisplayName>-<YYYY-MM-DDTHH-MM-SSZ>.csv`
- YAML namespace-scoped: `<Kind>-<Namespace>-<Name>-<YYYY-MM-DDTHH-MM-SSZ>.yaml`
- YAML cluster-scoped: `<Kind>-<Name>-<YYYY-MM-DDTHH-MM-SSZ>.yaml`

`ClusterDisplayName` is the value from `ClusterStripPin.displayName` (ADR-0051). Spaces in the
display name are replaced with hyphens; non-ASCII characters are percent-encoded.

`Kind` is the Kubernetes kind string as-is (e.g. `Deployment`, `PersistentVolume`).

Collisions are resolved by the `NSSavePanel` native increment logic (`(2)`, `(3)` suffix).

### Audit log entries

Every export operation (both CSV and YAML) produces a signed audit log entry via `AuditLogPort`
consistent with the ADR-0047 HMAC keychain chain.

CSV export entry fields:
- `action`: `export-list-csv`
- `kind`: the Kubernetes kind string
- `clusterDisplayName`: from `ClusterStripPin.displayName`
- `namespace`: the active namespace filter value, or `(all)` if none
- `rowCount`: the number of rows exported
- `destinationPath`: the resolved absolute file path chosen by the operator
- `timestamp`: RFC 3339

YAML export entry fields:
- `action`: `export-resource-yaml`
- `kind`: the Kubernetes kind string
- `name`: the resource name
- `namespace`: the resource namespace, or `(cluster-scoped)` for cluster-scoped resources
- `clusterDisplayName`: from `ClusterStripPin.displayName`
- `redacted`: boolean (always `true` for non-Secret kinds; the opt-in flag value for Secrets)
- `destinationPath`: the resolved absolute file path
- `timestamp`: RFC 3339

### Export domain model

The export operations are ApplicationService-level orchestration in the `resource_browser`
bounded context:

- `ListExportService` — ApplicationService. Serialises the visible row list to CSV bytes.
  Receives the `[ResourceRow]` snapshot and a `KindExportConfig` (column subset per kind family).
  Returns `Data`.
- `ResourceYAMLExportService` — ApplicationService. Fetches the live manifest via
  `KubernetesApiPort`, applies `SecretRedactionPolicy`, serialises via `Yams`. Returns `Data`.
- `SecretRedactionPolicy` — DomainService. Stateless. Accepts a parsed `[String: Any]` manifest
  map and an `ExportRedactionPreference` enum (`redacted` / `unredacted`). Returns the
  transformed manifest.
- `KindExportConfig` — Value. Defines the ordered column list for a given kind family.
  Constructed at startup from a static table; not configurable by the operator in this version.
- `ExportAuditEntryFactory` — DomainService. Constructs the typed audit entry for CSV and YAML
  exports; injects into `AuditLogPort`.

### Consequences

Positive:

- Operators can export auditable snapshots of resource lists without leaving the application.
- Per-row YAML export removes the need for `kubectl get -o yaml` for quick spec inspection and
  ticket-attachment workflows.
- Redaction-by-default for Secrets prevents inadvertent credential exposure in export artefacts.
- Audit log coverage (ADR-0047) ensures every export leaves a traceable record.

Negative:

- CSV column subsets are hard-coded per kind family. Operators who want different columns must
  use `kubectl` or wait for a future column-configurability ADR.
- YAML export fetches a fresh manifest on demand; on slow or unreachable clusters the fetch may
  time out. The UX must degrade gracefully (error toast, no `NSSavePanel` opened).
- The Secret redaction dialog adds one extra interaction for the common case (non-Secret YAML
  export is frictionless; Secret export requires an explicit confirmation step).
- `ListExportService` serialises the already-filtered, in-memory row list. It does not
  re-query the Kubernetes API for a fresh server-side snapshot of the full resource list. An
  operator who exports a list that was loaded 20 minutes ago receives data that may be stale.
  A `Last refreshed <timestamp>` annotation is included in the CSV header comment to make
  staleness transparent.

## Pros and cons of the options

### Option A — CSV export only

- Good, because it covers the tabular audit use case with minimal implementation surface.
- Bad, because the paste-into-ticket YAML workflow remains unsatisfied; operators still need
  `kubectl` for single-resource YAML export.

### Option B — YAML export only

- Good, because it covers the single-resource ticket workflow directly.
- Bad, because exporting a list of 200 Pods as 200 individual YAML documents is unusable in
  a spreadsheet context.
- Bad, because it does not reduce the `kubectl` dependency for tabular list inspection.

### Option C — Both (chosen)

- Good, because CSV and YAML serve orthogonal use cases; neither is a substitute for the other.
- Good, because the per-row YAML action integrates naturally into ADR-0061's canonical action menu.
- Bad, because two export codepaths must be implemented and maintained.

## Confirmation

- `contexts/resource_browser/schemas/kind_export_config.cue` defines `#KindExportConfig` with
  validated column subset lists per kind family. CI validates via `cue:vet`.
- `ListExportService` unit tests assert: correct header row, correct column order, RFC 4180
  quoting of commas in values, semicolon serialisation of multi-value fields, CRLF line endings,
  correct row count matching the filtered input.
- `ResourceYAMLExportService` unit tests assert: fetched manifest is passed through
  `SecretRedactionPolicy` for Secret kind; non-Secret kinds bypass redaction; `Yams`
  re-serialisation produces valid YAML with a leading `---` document marker.
- `SecretRedactionPolicy` unit tests assert: `data` values replaced with `[redacted:sha256:...]`
  placeholders under `redacted` preference; `stringData` always empty regardless of preference;
  all other fields preserved unchanged.
- Gherkin feature `contexts/resource_browser/features/list-export-csv.feature` covers the five
  scenarios below and is validated in CI.
- Audit log entries are verified in integration tests: CSV export produces one entry with `action`
  `export-list-csv`; YAML export produces one entry with `action` `export-resource-yaml`.

## Followups

- ADR-0061 — Per-row resource action menu uniform shape: the `Save YAML` menu item is one of the
  canonical items that ADR-0061 normalises across all kind families. The two ADRs must align on
  the exact label and menu position.
- ADR-0063 — Secret data presentation: ADR-0063 specifies the per-key reveal/hide toggle in the
  detail drawer. The `ExportRedactionPreference` opt-in checkbox defined here is a complementary
  but distinct control surface; the two must share the same `SecretRedactionPolicy` domain
  service to avoid divergent redaction logic.
- Column configurability — operators currently receive a fixed column subset. A future ADR may
  allow per-kind column selection, persisted in the per-cluster view state (ADR-0026).
- Multi-resource YAML export — exporting a checked bulk selection as a multi-document YAML file
  is deferred. If introduced, it belongs in a separate ADR that also addresses the checkbox
  bulk-select feature (R20 gap).

## More information

- ADR-0013 — Resource browser scope and kinds; original operation surface extended here.
- ADR-0019 — Adopted Swift libraries; `Yams` is used for YAML serialisation.
- ADR-0030 — Integrated editor; `Yams` and `swiftkube` adapter are the same dependencies.
- ADR-0047 — Audit chain HMAC keychain; export audit entries are signed via this chain.
- ADR-0050 — Resource navigation taxonomy; defines the list view context in which the download
  icon lives.
- ADR-0051 — Multi-cluster workspace; `ClusterStripPin.displayName` is the source of the cluster
  name in filename templates.
- ADR-0053 — Global namespace filter; the active filter determines which rows appear in the CSV.
- ADR-0061 — Per-row resource action menu; `Save YAML` is one of the canonical menu items.
- ADR-0063 — Secret data presentation (redaction detail for the detail drawer complement).
- `contexts/resource_browser/features/list-export-csv.feature`
- `contexts/resource_browser/schemas/kind_export_config.cue`
