# ADR-0056 — Kubeconfig import from clipboard

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0003 (kubeconfig read-only), ADR-0054 (Welcome tab and cluster-acquisition entry surface)
- Tags — kubeconfig, clipboard, paste, cluster-acquisition, cluster-connectivity

## Context and problem statement

Operators frequently receive kubeconfig fragments via Slack messages, email threads, or CI
pipeline log outputs. The conventional workaround is to save the pasted text to a temporary file,
point `KUBECONFIG` at it, and reload the application. This is friction-heavy and leaves temporary
credential files on disk longer than necessary.

ADR-0003 establishes that the application never writes kubeconfig material to the filesystem
without explicit user action; it does not, however, prohibit in-memory parsing of kubeconfig YAML
that the user supplies voluntarily. The gap analysis (R10, section 5.2 of
`feature-gap-analysis-lens-prism-ai.md`) identifies this flow as MISSING.

ADR-0054 specifies a Welcome tab that surfaces five cluster-acquisition actions. One of those
actions is "Add kubeconfig from clipboard". This ADR defines the technical contract for that
action.

## Decision drivers

- **Security — never write the pasted material to the filesystem unless the user explicitly
  accepts the import** — the clipboard YAML is parsed and validated entirely in memory; the only
  persistence path is the existing per-cluster store (ADR-0026) triggered by a deliberate Import
  confirmation.
- **Security — never log full kubeconfig content** — log entries and error reports must reference
  only sanitised cluster display names (e.g., `my-cluster`) and error codes; raw YAML, bearer
  tokens, client-certificate PEM blocks, and exec-plugin arguments must never appear in any log
  line, crash report, or Diagnostics export (ADR-0041).
- **UX — operators paste; they do not type** — the import sheet must not require the operator to
  identify individual fields; it must parse the full kubeconfig YAML blob and derive its structure
  automatically.
- **UX — validation must be immediate and actionable** — if the pasted YAML is invalid, the error
  must show the line number of the first failure and a plain-English description, without forcing
  the operator to dismiss the sheet and re-paste.
- **Minimal new surface** — the import path reuses `YamsKubeconfigAdapter` (the same adapter used
  for disk-based kubeconfig loading) and the existing cluster-connectivity import pipeline; no new
  parsing or persistence mechanism is introduced.

## Considered options

- **Option A** — In-memory parse via `YamsKubeconfigAdapter` presented in a modal validation
  sheet; on accept, call the existing `cluster_connectivity` import path. No temp file.
- **Option B** — Write clipboard content to a system temp file under `/var/folders/…/` and hand
  the path to the existing disk-based load pipeline; delete the temp file on completion or
  cancellation.
- **Option C** — Provide a multi-line text editor inside the Welcome tab body where the operator
  can paste and edit YAML before submitting.

## Decision outcome

Chosen option — **Option A**, because:

- No credential material ever touches the filesystem as an intermediate step; Option B creates a
  window of exposure even with immediate deletion.
- Option C increases the editing surface and tempts the operator to handcraft YAML, which is
  error-prone and outside the intended workflow.
- Option A reuses `YamsKubeconfigAdapter` without any new adapter or persistence layer; the
  clipboard is the only input, and acceptance triggers the standard import path.

### Clipboard import contract

1. The operator invokes the "Add kubeconfig from clipboard" action from the Welcome tab or the
   cluster strip `+` button.
2. The application reads the current `NSPasteboard.general` string. If the pasteboard is empty or
   does not contain a plain-text (`.string` type) value, an inline message is shown immediately
   inside the sheet: "Clipboard is empty. Copy a kubeconfig YAML and try again." No modal is
   dismissed; the operator can copy to clipboard and retry without reopening the sheet.
3. The pasteboard string is passed synchronously to `YamsKubeconfigAdapter.parse(_:)`.
   Parsing runs on a background `Task`; the sheet shows an indeterminate progress indicator
   during this phase (expected to complete in under 50 ms for any realistic kubeconfig).
4. If parsing fails, the validation sheet renders the error state (see Validation sheet UI shape
   below). The operator can correct the source, re-copy, and press "Paste from Clipboard" again
   inside the same sheet to retry.
5. If parsing succeeds, `YamsKubeconfigAdapter` runs structural validation:
   - Every declared context must reference an existing cluster entry in `clusters[]`.
   - Every declared context must reference an existing user entry in `users[]`.
   - At least one context must be present (`contexts[]` non-empty).
   - Every cluster entry must carry a non-empty `server` URL that parses as an `https://` or
     `http://` URL (the application does not perform network reachability at this stage).
   - If an `exec` block is present in any user entry, it must carry a non-empty `command` field.
6. Structural validation failures are displayed as named-error markers in the validation sheet
   (see below). All failures are displayed at once; the operator does not fix one at a time.
7. If validation passes, the sheet shows a summary of discovered entries:
   - Cluster count (e.g., "2 clusters found").
   - Context count (e.g., "3 contexts found").
   - Current context name (if `current-context` is set in the pasted YAML).
   - Detected provider hint per cluster (derived from exec-block command pattern:
     `aws`, `az`, `gcloud`, `kubelogin` → AKS, EKS, GKE, OIDC; no exec block → Local).
8. The operator presses "Import". The application calls the existing cluster-connectivity import
   path, which merges the parsed entries into the per-cluster store under ADR-0026. Conflicts with
   existing clusters (same cluster server URL or same context name already stored) trigger the
   conflict resolution flow (see Reject paths below).
9. On successful import the sheet is dismissed. The new clusters appear in the cluster strip and
   the sidebar tree. A toast notification confirms: "N cluster(s) added from clipboard."

### Validation sheet UI shape

The validation sheet is a `NSPanel` (sheet-style, attached to the main window) with three zones:

- **Header** — sheet title "Import kubeconfig from clipboard" plus a one-line description.
- **Content area** — renders in one of three states:
  - Empty pasteboard: inline plain-text message (no YAML display area).
  - Parse or validation error: a read-only text view showing the pasted YAML with a line-number
    gutter on the left (monospaced, 12 pt). Invalid lines are highlighted in
    `systemRed`/`systemOrange` (parse errors vs structural errors). Named-error markers appear as
    a callout list below the text view, each with an icon, the error code, the line number (if
    applicable), and a plain-English description.
  - Validation passed: the summary table described in step 7 of the import contract.
- **Footer** — action buttons:
  - "Paste from Clipboard" — re-reads `NSPasteboard.general` and reruns parse/validation.
  - "Cancel" — dismisses the sheet; no state is persisted; clipboard content is not cleared.
  - "Import" — enabled only when validation has passed; triggers step 8 of the import contract.

The validation sheet must be keyboard-navigable: Tab moves between buttons; Return activates
the focused button; Escape is equivalent to "Cancel".

### Reject paths

- **Invalid YAML** — parse fails; error state rendered in the content area. No import occurs.
- **Missing required entries** — `contexts[]` is empty, or a context references an unknown cluster
  or user; structural validation error rendered; no import occurs.
- **Conflict with existing cluster** — a cluster server URL or context name from the pasted YAML
  matches an entry already in the per-cluster store. The conflict is surfaced in the summary table
  with a warning badge. The operator can choose:
  - "Rename and add" — the conflicting context name is suffixed with a numeric disambiguator
    (e.g., `production-1`). The operator may edit the proposed name before confirming.
  - "Replace existing" — the existing cluster entry is overwritten. A secondary confirmation
    ("This will replace the existing cluster 'production'. Are you sure?") is required, consistent
    with the double-confirm policy in ADR-0012.
  - "Skip" — the conflicting entry is excluded from the import; non-conflicting entries proceed.

### Security note

- The application must never include full kubeconfig YAML, bearer tokens, client certificate PEM
  blocks, or exec-plugin credential output in any log line, crash report, analytics event, or
  Diagnostics export. When logging import activity, only the sanitised cluster display name
  (derived from the kubeconfig `name` field) and a boolean success/failure indicator are recorded.
- Clipboard content is read exactly once per "Paste from Clipboard" press; the application does
  not retain a reference to the pasteboard string beyond the parse-and-validate cycle. After
  successful import the in-memory parsed representation is held only for the duration of the
  cluster-connectivity import call and then released.
- The validation sheet must not render exec-plugin credential output, bearer token values, or
  client certificate data in any visible text field. If the pasted YAML contains inline credential
  material (e.g., embedded base64 certificates), the summary table renders only the field names
  (e.g., "client-certificate-data: present") and not the values.

## Pros and cons of the options

Positive:

- Operators can connect a cluster in seconds by pasting from Slack or email, with no temp file
  and no filesystem write until they press Import.
- Validation errors are shown inline with line numbers, matching the UX established for the
  existing disk-based error reporting (`load-kubeconfig.feature` scenario "Malformed YAML surfaces
  an actionable error").
- No new parsing or persistence infrastructure is required; `YamsKubeconfigAdapter` and the
  cluster-connectivity import path are reused.

Negative:

- The validation sheet is a new UI surface that must be tested against all reject paths and
  keyboard-navigation requirements.
- Conflict resolution adds conditional UI state (rename vs replace vs skip) that must be
  specified carefully to avoid surprising the operator when a context name collides.

## Confirmation

- Gherkin feature `cluster_connectivity/features/kubeconfig-paste-from-clipboard.feature`
  covers: valid paste → import; empty clipboard; non-YAML clipboard content; conflict with
  existing cluster offering rename/replace.
- `YamsKubeconfigAdapter` unit tests cover parsing of multi-cluster and multi-context blobs,
  structural validation failures, and sanitised error output (no credential material in error
  messages).
- An integration test mocks `NSPasteboard.general` with a valid two-cluster kubeconfig, invokes
  the import sheet programmatically, presses "Import", and asserts that both clusters appear in
  the cluster strip and sidebar tree.
- A security test asserts that no logger call site (OSLog, Console, DiagnosticsExport) emits a
  string containing known token/certificate fixtures from the test kubeconfig.

## Followups

- ADR-0054 (Welcome tab) must list "Add kubeconfig from clipboard" as one of the five
  cluster-acquisition actions and wire it to the sheet described here.
- The conflict-resolution rename flow should share its UX shape with any future cluster-rename
  feature (not yet specified) to avoid divergent rename dialogs.
- The validation sheet YAML viewer is a candidate for extraction as a reusable
  `YAMLValidationView` component, which could also back the YAML editor error state in ADR-0030.

## More information

- ADR-0003 — Kubeconfig is read-only; no credential persistence. This ADR extends the
  clipboard-paste case: the user voluntarily supplies the YAML, so parsing is permitted; the
  read-only contract is satisfied because no kubeconfig file on disk is mutated.
- ADR-0026 — State persistence and filesystem layout; the per-cluster store is the only
  persistence target for successfully imported clusters.
- ADR-0030 — Integrated editor; the YAML validation view component may share code with the
  editor's error pane.
- ADR-0051 — Multi-cluster workspace; the cluster strip `+` button is a secondary entry point
  for this flow in addition to the Welcome tab.
- ADR-0054 — Welcome tab and cluster-acquisition entry surface; defines the five start actions
  including "Add kubeconfig from clipboard".
- Feature gap analysis — `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`,
  reference item R10.
