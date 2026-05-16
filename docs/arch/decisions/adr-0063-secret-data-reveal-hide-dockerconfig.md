# ADR-0063 — Secret data presentation (reveal, hide, dockerconfigjson parser)

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none)
- Informed — (none)
- Refines — ADR-0047 (audit chain HMAC keychain), ADR-0012 (mutating operations policy),
  ADR-0050 (resource navigation taxonomy)
- Tags — secrets, reveal, dockerconfigjson, audit, resource-browser

## Context and problem statement

The feature-gap analysis (`feature-gap-analysis-lens-prism-ai.md`, R32) records that the Lens
reference UI presents the Secret detail drawer with a per-key reveal/hide affordance: every key in
the `data` map is hidden by default, an eye icon per key reveals the decoded value inline, and for
`kubernetes.io/dockerconfigjson` the rendered value is the parsed JSON with `auths`, username, and
password rows. A copy-to-clipboard button is available next to each key row.

K8S-Manager's Secret list view and view models exist today but the reveal/hide affordance is not
implemented. Secret `data` values are base64-encoded by the Kubernetes API and contain operational
credentials (registry passwords, TLS private keys, database connection strings, SSH keys). Revealing
these values in the UI is a privileged read action, and the compliance posture of the project
(ADR-0047, ADR-0012) requires that privileged actions are auditable.

The secondary question is whether specific well-known Secret types should be rendered in a richer
format rather than as raw decoded bytes. The recording confirms that `kubernetes.io/dockerconfigjson`
deserves first-class rendering. The `kubernetes.io/tls` type warrants certificate metadata decoding
for the `tls.crt` key, while `tls.key` must remain always-hidden unless the operator explicitly
reveals it.

## Decision drivers

- **Operator utility** — operators need to inspect Secret values during debugging without leaving
  the application and running `kubectl get secret -o json | jq`.
- **Security by default** — decoded values must never appear in the UI before a deliberate reveal
  gesture; no value is pre-rendered to the screen on drawer open.
- **Audit trail required** — every reveal is a privileged read of a potentially sensitive credential;
  the action must be persisted to the audit log for compliance review, consistent with the mutation
  audit established in ADR-0012 and the HMAC chain established in ADR-0047.
- **Values never logged in plain text** — reveal operations must not surface decoded values in any
  application log, diagnostic export, or crash report.
- **Clipboard hygiene** — copied values must not persist in the system clipboard beyond 90 seconds.
- **Type-aware rendering** — raw base64 blobs are harder to act on than a rendered table; known
  types should be decoded to structured views that expose the operationally relevant fields.
- **Bulk reveal disabled** — batch-revealing all keys at once widens the blast radius of an
  inadvertent screen share or screenshot; each key must be revealed individually.

## Considered options

- **Option A — Always reveal (current Lens partial behaviour):** display decoded values immediately
  on drawer open, with no per-key toggle.
- **Option B — Hide by default, per-key reveal with audit log (chosen):** all values are masked on
  drawer open; each key has an eye icon; clicking reveals that key's value inline; the action is
  persisted to the audit log with an HMAC-chained entry; revealed value auto-hides after 60 seconds
  of application focus loss.
- **Option C — Reveal requires re-authentication via system password:** the operator must enter
  their macOS user password (via `LAContext.evaluatePolicy`) before any value is decoded and shown.

## Pros and cons of the options

### Option A — Always reveal

- Good, because the operator can inspect values without any extra click.
- Bad, because any screen share or shoulder-surf during normal drawer use exposes the value.
- Bad, because there is no audit trail; compliance requirements are not met.
- Bad, because the clipboard copy path has no hygiene window.

### Option B — Hide by default + per-key reveal + audit log (chosen)

- Good, because the masked-by-default posture minimises accidental exposure during screen sharing.
- Good, because the audit log satisfies the compliance requirement with no added credential prompt
  friction.
- Good, because the auto-hide timer limits exposure duration without requiring operator action.
- Good, because type-aware rendering (dockerconfigjson, tls.crt) adds operational value.
- Neutral, because the 60-second auto-hide may require re-reveal for slow copy-paste workflows;
  this is acceptable given the security trade-off.
- Bad, because the audit schema extension requires a new event kind alongside the mutation audit.

### Option C — Re-authentication per reveal

- Good, because the system password gate provides the strongest intent signal.
- Bad, because the friction is disproportionate for routine debugging; operators would work around
  it by defaulting to `kubectl`.
- Bad, because `LAContext` is biometric/password and is meaningless for headless CI contexts or
  for operators who legitimately use the application on a shared workstation.
- Bad, because it does not solve clipboard hygiene after the initial reveal.

## Decision outcome

**Chosen option: B — hide by default, per-key reveal with audit log.**

Rationale: it satisfies the security-by-default requirement, closes the compliance gap without
adding authentication friction, and provides the type-aware rendering needed for
`kubernetes.io/dockerconfigjson` and `kubernetes.io/tls`.

### Reveal flow contract

On Secret detail drawer open, every key in the `data` map is rendered as:

```
[key name]   ••••••••   [eye icon]   [copy icon]
```

The eye icon carries the accessibility label "Reveal value for key <key-name>".

**Single-key reveal sequence:**

1. Operator clicks the eye icon for a specific key.
2. The application decodes the base64 value in memory (never to disk, never to any log).
3. The value replaces the masked placeholder inline. The eye icon label flips to "Hide value for
   key <key-name>".
4. An audit log entry is written (see audit log entry shape below).
5. If the operator clicks the eye icon again (now labelled "Hide"), or if the application window
   loses focus for 60 continuous seconds, the value is cleared from the rendered view and the
   placeholder is restored.
6. The decoded bytes are released from memory when the view is hidden.

**Clipboard copy sequence:**

1. Operator clicks the copy icon while a value is revealed.
2. The decoded value is written to `NSPasteboard.general`.
3. A toast notification confirms "Copied to clipboard — will clear in 90 s."
4. An audit log entry is written with `action: clipboard-copy` (see audit log entry shape below).
5. After 90 seconds, `NSPasteboard.general` is cleared if and only if the pasteboard still contains
   exactly the value that was copied (ownership check via `NSPasteboard.changeCount`).

**Bulk reveal disabled:** there is no "Reveal all" button. The eye icon is present only at the
individual key row level. A bulk-reveal attempt is not surfaced in the UI.

**Auto-hide timer:** the 60-second focus-loss timer is per-drawer, not per-key. When the main
application window regains focus, the timer resets. The timer does not apply when the application
is in foreground and the operator is actively scrolling the drawer.

### Audit log entry shape

The reveal and clipboard-copy actions produce entries in a new `secret_reveal_audit` SQLite table
(owned by `local_persistence`, separate from `cluster_mutation_audit` to keep the mutation chain
clean). Each entry is HMAC-chained per ADR-0047 using the same `AuditChainKeyManager` and the same
`kSecAttrService` item (`com.archanjo.K8sManager.audit`).

Mandatory fields per entry:

- `id` — UUIDv7 generated at action time.
- `requestedAt` — RFC3339 timestamp.
- `action` — one of `reveal`, `hide`, `clipboard-copy`, `auto-hide`.
- `clusterId` — UUIDv7 of the active cluster context.
- `namespace` — the Secret's namespace.
- `secretName` — the Secret's name.
- `keyName` — the specific data key that was revealed or copied.
- `secretType` — the value of `type` from the Secret's metadata (e.g., `kubernetes.io/dockerconfigjson`).
- `userIdentifier` — the macOS `NSUserName()` value at reveal time.
- `previousEntryDigest` — 64-character lowercase HMAC-SHA256 hex chain link per ADR-0047.
- `entryDigest` — 64-character lowercase HMAC-SHA256 hex of this entry.

The decoded secret value itself is **never** stored in any audit field. The audit entry records
only that a key was accessed, not what the value was.

### Special type parsers

#### kubernetes.io/dockerconfigjson

When the Secret type is `kubernetes.io/dockerconfigjson`, clicking the eye icon for the
`.dockerconfigjson` key reveals a structured table instead of the raw JSON string:

```
Registry           Username     Password
registry.io        alice        ••••••••   [eye]
ghcr.io            bob          ••••••••   [eye]
```

The password column is masked by default within the rendered table. Each password cell has its own
eye icon that follows the same per-key reveal sequence described above. The audit log entry for the
`.dockerconfigjson` key uses `keyName: ".dockerconfigjson"`. If the operator reveals a specific
registry's password within the rendered table, a second audit entry is written with
`keyName: ".dockerconfigjson.auths.<registry>.password"`.

Parsing rules:

1. Decode the base64 value of `.dockerconfigjson`.
2. Parse as JSON. If parsing fails, fall back to rendering the raw decoded string with an inline
   error badge "Invalid JSON — raw value shown."
3. Navigate to `.auths` (or `.Auth` for legacy format). If absent, fall back to raw rendering.
4. For each registry key in `.auths`, extract `.username` (or decode `.auth` as `user:pass` Base64
   if `.username` is absent) and `.password` (or the password component of `.auth`).
5. Render one row per registry. Empty username or password cells show an em dash.

#### kubernetes.io/tls

When the Secret type is `kubernetes.io/tls`:

- `tls.crt` — reveal shows the PEM block. Below the PEM block, the application decodes the first
  certificate in the chain using the Security framework and renders a metadata summary:
  - Subject (CN, O, OU if present)
  - Issuer (CN, O)
  - Valid from / Valid until (RFC3339 dates, with a "Expired" or "Expires in N days" badge)
  - Serial number (hex)
  - Key usage and extended key usage (if present)

  The PEM text itself is shown as a monospaced block. The decoded metadata summary is read-only and
  is not itself considered a reveal (metadata is not sensitive); however, the eye icon on `tls.crt`
  is still required before any of this is rendered, because the PEM block is sensitive.

- `tls.key` — always rendered as masked by default with an explicit eye icon. There is no type-aware
  rendering for `tls.key`; the eye icon reveals the raw decoded PEM string only. The audit event
  for `tls.key` reveal carries the same structure but `secretType: kubernetes.io/tls` and
  `keyName: "tls.key"`.

#### All other types

For all other Secret types (`Opaque`, `kubernetes.io/basic-auth`, `kubernetes.io/ssh-auth`,
`bootstrap.kubernetes.io/token`, or custom types), each key is rendered as a plain masked row with
the eye icon. Clicking the eye icon for a key reveals the decoded UTF-8 string if the value is
valid UTF-8, or a hex dump if not.

## Confirmation

- Unit test: `SecretDataRevealViewModel` starts with all keys masked.
- Unit test: reveal eye-icon click for a single key transitions that key's state to revealed; other
  keys remain masked.
- Unit test: hide eye-icon click re-masks the revealed key.
- Unit test: focus-loss for 60 seconds triggers auto-hide for all currently revealed keys and emits
  `action: auto-hide` audit entries.
- Unit test: clipboard copy writes the correct decoded value to `NSPasteboard.general` and schedules
  a 90-second clear; a subsequent pasteboard overwrite by a third party prevents the scheduled
  clear from clobbering the new value.
- Unit test: `DockerConfigJSONParser` correctly parses a standard `auths` map with `username` +
  `password` fields.
- Unit test: `DockerConfigJSONParser` correctly decodes a legacy `auth` base64 field into username
  and password components.
- Unit test: `DockerConfigJSONParser` returns a `ParseError` for malformed JSON input.
- Unit test: TLS `tls.crt` decode renders subject, issuer, validity, and serial number correctly
  for a self-signed test certificate.
- Integration test: reveal action writes a `secret_reveal_audit` entry with the correct HMAC chain
  link and `keyName`, and does not include the decoded value.
- Integration test: `clipboard-copy` audit entry is written; 90-second clear fires if the
  pasteboard has not been overwritten.
- Spec lane: `spec validate --lane audit` covers `secret_reveal_audit` in addition to
  `cluster_mutation_audit`.

## Followups

- Define retention policy for `secret_reveal_audit` (parallel to the mutation audit retention
  decision deferred in ADR-0012).
- Evaluate whether `kubernetes.io/basic-auth` and `kubernetes.io/ssh-auth` warrant type-specific
  renderers (structured username/password row and public-key fingerprint, respectively) in a future
  follow-on ADR.
- Assess whether the audit entries for reveal actions should be exportable as CSV alongside the
  mutation audit export defined in ADR-0060.
- Consider whether the `tls.crt` certificate validity badge ("Expires in N days") should feed the
  notification bell (ADR-0051 top-right chrome) when a certificate is close to expiry.

## More information

- ADR-0047 — Audit chain HMAC-SHA256 with Keychain-stored key (HMAC chain, `AuditChainKeyManager`,
  `secret_reveal_audit` must use the same key manager).
- ADR-0012 — Mutating operations policy (audit log write contract; this ADR extends the audit
  surface to read-reveal events).
- ADR-0050 — Resource navigation taxonomy (Secret is in the Config category of the sidebar tree).
- ADR-0051 — Multi-cluster workspace (detail drawer layout; `ResourceDetailDrawer` is the host
  view for the Secret data section).
- Feature-gap analysis R32 — `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`.
