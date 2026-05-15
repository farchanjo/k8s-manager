# ADR-0026 — State persistence and filesystem layout under `~/.config/k8smanager/`

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0010 (local persistence — SQLite for non-secret state, macOS Keychain for LLM API keys)
- Tags — persistence, filesystem, storage-path, xdg, cold-launch, restoration

> **Refinement note (2026-05-15).** ADR-0010 placed the SQLite storage
> file under `~/Library/Application Support/com.archanjo.K8sManager/`.
> This ADR moves the storage root to `~/.config/k8smanager/` (XDG-style,
> operator-friendly path). macOS convention would normally mandate
> `~/Library/Application Support/com.archanjo.K8sManager/`, but the
> target operator profile (DevOps / platform engineers) expects
> `~/.config`-style paths that are immediately discoverable, easy to
> back up with a single `tar`, and compatible with dotfile management
> workflows. The Keychain placement is unchanged — Keychain is OS-managed
> and is the correct and most secure home for secret material. All other
> rules from ADR-0010 (WAL mode, GRDB, migrations, redaction policy)
> carry forward without change.

## Context and problem statement

ADR-0010 established the storage strategy (SQLite + macOS Keychain) but
fixed the file location at
`~/Library/Application Support/com.archanjo.K8sManager/storage.sqlite3`.
As development continued, three additional requirements emerged:

- **Per-cluster view state** — ADR-0025 introduces per-cluster view
  state (sidebar expansion, content scroll position, detail tab
  selection, namespace filter, search query) that must be persisted and
  restored independently per cluster. Placing these inside the monolithic
  SQLite file is possible but makes per-cluster reset and operator
  inspection awkward.
- **Cold-launch restoration** — the application must restore on startup:
  active navigation context, pinned cluster sessions, dashboard layouts,
  chat sessions, terminal sessions (with opt-in prompt), and port-forward
  listeners (with opt-in prompt). A structured restoration manifest
  simplifies the boot sequence.
- **Operator-friendly path** — the target operator works daily with
  `~/.kube/config`, `~/.config/starship.toml`, `~/.config/gh/hosts.yml`.
  The `~/Library/Application Support` hierarchy is opaque to CLI
  operators and requires Finder navigation. A `~/.config/k8smanager/`
  root is in band with the operator's existing tooling.

Additionally, a first-run migration path is needed for operators who
already have a storage file at the `~/Library/Application Support`
location from an earlier build.

## Decision drivers

- **Operator discoverability** — `~/.config/k8smanager/` is reachable
  from the terminal without navigating macOS-specific Finder locations.
- **Backup simplicity** — `tar -czf k8smanager-backup.tar.gz ~/.config/k8smanager/`
  captures the complete application state (excluding Keychain secrets,
  which are OS-managed and inapplicable to file backup).
- **Per-cluster isolation** — per-cluster view state and restorable
  session data live under `clusters/<clusterId>/` so that removing a
  cluster context removes exactly one subtree.
- **Privacy by design** — log files must not contain credential material;
  cache data must be clearable independently of application preferences
  and chat history.
- **Atomic writes** — per-cluster JSON files must survive a hard crash
  without corruption; write-to-tmp-then-rename is the standard approach.
- **Migration safety** — operators who ran an earlier build must not lose
  data; a first-run prompt offers a one-time migration.

## Considered options

### Option A — `~/Library/Application Support/com.archanjo.K8sManager/` (ADR-0010 baseline)

Keep the macOS-conventional path.

**Pros**

- Aligns with Apple platform conventions.
- Automatic exclusion from iCloud Desktop & Documents sync
  (App Support is not synced by default).
- Sandbox-compatible if the app is ever submitted to the App Store.

**Cons**

- Opaque to CLI operators; not discoverable without Finder.
- Longer path; does not integrate with dotfile managers or `stow`.
- `tar` backup requires knowing the bundle identifier.
- Inconsistent with the rest of the operator's `~/.config`-centric
  toolchain.

### Option B — Dot-folder in `$HOME` (e.g., `~/.k8smanager/`)

Place the storage root directly in `$HOME` as a hidden dot-folder.

**Pros**

- Single path component; easy to remember.
- Compatible with dotfile workflows.

**Cons**

- `$HOME` dot-folder proliferation is a known usability anti-pattern
  (XDG was introduced precisely to reduce this).
- No separation between application data, cache, and logs.
- Conflicts with any other tool that chose `~/.k8smanager` as its
  config path.

### Option C — XDG `~/.config/k8smanager/` (chosen)

Use the XDG Base Directory convention for the root. Although macOS does
not standardise on XDG, the operator population (DevOps / platform
engineers) universally encounters `~/.config` through tools such as
`gh`, `starship`, `lazygit`, `k9s`, `kubectx`, and `helm`.

**Pros**

- Discovered instantly by operators who know `~/.config`.
- Clean separation of persistent state (root), caches
  (`cache/`), per-cluster state (`clusters/`), logs (`logs/`),
  and operator-initiated exports (`exports/`).
- `tar -czf k8smanager-backup.tar.gz ~/.config/k8smanager/` captures
  everything except Keychain secrets.
- Per-cluster subtree under `clusters/<clusterId>/` maps directly
  onto the ADR-0025 `#ClusterSession` lifecycle.
- Compatible with `chezmoi`, `stow`, and similar dotfile managers.

**Cons**

- Deviates from Apple's recommended `~/Library/Application Support`
  convention; some App Store review guidelines refer to this path.
  K8sManager is a Developer ID–distributed app (ADR-0004), so App
  Store sandbox constraints do not apply.
- Application sandbox must explicitly declare the `~/.config`
  entitlement (`com.apple.security.temporary-exception.files.home-relative-path.read-write`
  or a hardened-runtime equivalent).

## Decision outcome

The storage root for K8sManager is `~/.config/k8smanager/`. The
directory is created on first launch with `0700` permissions.

### Complete filesystem layout

```
~/.config/k8smanager/
├── storage.sqlite3            # Main SQLite database (WAL, GRDB, ADR-0010 rules)
├── storage.sqlite3-wal        # WAL sidecar (managed by SQLite)
├── storage.sqlite3-shm        # Shared-memory sidecar (managed by SQLite)
├── cache/                     # Transient caches — safe to delete; reset on app version bump
│   ├── resource_list/         # Kubernetes resource list responses (TTL-keyed)
│   └── prometheus/            # Prometheus query result cache (TTL-keyed)
├── clusters/
│   └── <clusterId>/           # One directory per cluster (clusterId is a UUIDv7)
│       ├── view_state.json    # Sidebar expansion, scroll pos, tab, ns filter, search query
│       ├── restorable_port_forwards.json   # Port-forwards to offer on cold launch
│       └── recent_resources.json           # Recently accessed resources for this cluster
├── logs/
│   └── <yyyy-mm-dd>.log       # Daily rotated app log; max 30 days retained
└── exports/                   # Operator-initiated exports (dashboard CSV, audit log CSV)
```

**Notes on individual entries:**

- `storage.sqlite3` — opened with `journal_mode=WAL`, `synchronous=NORMAL`,
  `foreign_keys=ON`, `busy_timeout=5000`, `cache_size=-65536`. Identical
  PRAGMAs to ADR-0010; only the path changes.
- `cache/` — the entire subtree is wiped on app version bump. Any
  cached value must be fully reconstructible from the cluster or from
  storage. Never put user-authoritative data in `cache/`.
- `clusters/<clusterId>/` — created when a `ClusterSessionActor` is
  first opened for that cluster; removed when the operator deletes the
  cluster context from the application.
- `view_state.json` — written atomically (write to
  `view_state.json.tmp`, then `rename(2)`) within 5 seconds of any
  state mutation (debounced). Never written on the main actor; the
  `ClusterSessionActor` (ADR-0025) issues the write.
- `restorable_port_forwards.json` — written atomically. Contains the
  minimal payload to re-establish port-forward listeners on next
  launch, subject to operator opt-in prompt.
- `logs/<yyyy-mm-dd>.log` — written by the logging subsystem; rotated
  at midnight; files older than 30 days are deleted by the weekly
  vacuum task. Log lines must not contain credential material (token
  values, kubeconfig paths with auth data, API key fragments). This is
  enforced by the `RedactionPolicy` (ADR-0010) applied to every
  log-message formatter.
- `exports/` — written only when the operator explicitly requests a
  CSV export; not backed up automatically.

### Keychain (unchanged)

Keychain entries remain under macOS Keychain with
`service = "com.archanjo.K8sManager.llm"` per ADR-0010. Keychain is
OS-managed; it is the correct home for secret material and is not part
of the `~/.config/k8smanager/` backup.

### Write rules

- **Debounced write** — any state mutation that is not safety-critical
  is coalesced into a single write within a 5-second window. This
  prevents continuous I/O churn when the operator scrolls rapidly.
- **Atomic write** — per-cluster JSON files use write-to-tmp-then-rename.
  The `tmp` file is written in the same directory as the target so that
  `rename(2)` is a same-filesystem operation and therefore atomic.
- **WAL for SQLite** — concurrent readers and the single `PersistenceActor`
  writer operate without blocking each other under WAL mode.
- **No credential material in files** — the `RedactionPolicy` scans
  every string before it lands in `storage.sqlite3` or any JSON file.
  Log formatters apply a secondary regex scrub before writing to disk.

### Cold-launch restoration flow

On every cold launch the application executes the following sequence:

```mermaid
sequenceDiagram
    participant App as Application bootstrap
    participant FS as Filesystem
    participant DB as storage.sqlite3
    participant Actor as ClusterSessionActor
    participant UI as MainActor (SwiftUI)

    App->>FS: Read RestorationManifest\n(clusters/<id>/view_state.json per pinned cluster)
    App->>DB: Open SQLite, run pending migrations
    App->>DB: Load ContextNavigationState (active context)
    App->>UI: Render initial shell with loading state

    loop For each pinned/recent cluster (parallel TaskGroup)
        App->>Actor: Spawn ClusterSessionActor
        Actor->>FS: Load view_state.json
        Actor-->>UI: Publish .connecting event
        Actor-->>UI: Publish .connected event (on success)
    end

    App->>DB: Load dashboard custom layouts
    App->>DB: Load chat sessions
    App->>UI: Restore dashboard layouts + chat session list

    alt openTerminalSessions count > 0
        App->>UI: Prompt "Reopen N terminals from last session?"
        UI-->>App: operator accepts
        App->>Actor: Reopen terminal sessions
    end

    alt openPortForwards count > 0
        App->>UI: Prompt "Reopen M port-forwards from last session?"
        UI-->>App: operator accepts
        App->>Actor: Reopen port-forward listeners
    end
```

### First-run migration path

On launch, before opening any storage, the application checks whether
the legacy storage file exists at
`~/Library/Application Support/com.archanjo.K8sManager/storage.sqlite3`.

If the legacy file is found **and** `~/.config/k8smanager/storage.sqlite3`
does not yet exist, the application presents a one-time migration prompt:

> "K8sManager found an existing database from a previous version at
> `~/Library/Application Support/com.archanjo.K8sManager/`.
> Move it to `~/.config/k8smanager/`?"
>
> [Move] [Start fresh]

If the operator confirms:

1. `~/.config/k8smanager/` is created.
2. `storage.sqlite3`, `storage.sqlite3-wal`, and `storage.sqlite3-shm`
   are moved (not copied) to the new location.
3. The legacy directory is left in place but empty, so that the operator
   can confirm the move and delete it manually.
4. A `#RestorationPrompt` record with `kind = "migrate_storage_path"`
   is persisted in the new database to record that migration occurred.

If the operator chooses "Start fresh":

1. `~/.config/k8smanager/` is created.
2. A fresh `storage.sqlite3` is initialised with the current schema.
3. The legacy directory is left untouched.

If neither file exists (fresh install): step 1 only; no prompt.

### Privacy note

The log files at `~/.config/k8smanager/logs/` are intended for
operator-facing diagnostics. They must not contain:

- Bearer tokens, client certificates, or kubeconfig-sourced credentials.
- LLM API key values or key fragments.
- Full content of Kubernetes secret objects.

The `RedactionPolicy` Rego rule enforces this for SQLite writes.
For log writes, every log-message formatter applies a secondary regex
pattern matching common credential shapes (base64-encoded JWT payloads,
`Bearer <token>`, `Authorization:` header values) and replaces matches
with `[REDACTED]`.

### Backup guidance

An operator wanting a full backup of application state (excluding
Keychain secrets and cluster credentials) runs:

```sh
tar -czf k8smanager-backup-$(date +%Y%m%d).tar.gz ~/.config/k8smanager/
```

To restore on a new machine: extract and launch the application. The
application will find the existing `storage.sqlite3` and skip the
migration prompt. Keychain entries (LLM API keys) must be re-entered
manually; this is the correct security posture.

### Consequences

**Positive**

- Storage root is immediately discoverable by CLI operators.
- Per-cluster state under `clusters/<clusterId>/` has a natural
  lifecycle tied to `ClusterSessionActor` from ADR-0025.
- `tar` backup is a single command without knowing the bundle
  identifier.
- Clearing the `cache/` subtree is safe at any time and resolves
  most storage-related support issues.
- Log rotation (daily, 30-day cap) prevents unbounded disk use.

**Negative**

- Deviates from Apple's `~/Library/Application Support` convention;
  the app must declare a hardened-runtime entitlement for
  `~/.config` access.
- Keychain backup is a separate workflow; operators must understand
  that the `tar` backup does not include their LLM API keys.
- First-run migration adds a conditional code path; it must be tested
  to prevent data loss.

**Neutral**

- The path change is transparent to the operator's existing workflows;
  nothing else in the application references the old path after
  migration.
- SQLite WAL sidecar files (`-wal`, `-shm`) are included in the `tar`
  backup and are safe to restore.

### Confirmation

- A cold-launch test on a fresh machine creates
  `~/.config/k8smanager/storage.sqlite3` and confirms `journal_mode`
  returns `wal`.
- A migration test places a legacy database at
  `~/Library/Application Support/com.archanjo.K8sManager/storage.sqlite3`,
  launches the app, confirms the migration prompt is shown, accepts,
  and asserts the file is present at the new path and absent from the
  old path.
- A per-cluster view-state test opens two cluster sessions, mutates
  view state in each, kills the app, relaunches, and asserts that
  both `view_state.json` files were restored correctly.
- A redaction test writes a log message containing a bearer token;
  asserts that the log file on disk contains `[REDACTED]` in place
  of the token value.
- A backup-restore test creates a backup `tar`, extracts it onto a
  fresh machine, launches the app, and confirms that chat history and
  dashboard layouts are present.

## More information

- ADR-0003 — Kubeconfig read-only; kubeconfig files are not moved or
  copied to `~/.config/k8smanager/`.
- ADR-0004 — Developer ID distribution; App Store sandbox is not
  applicable, freeing the XDG path choice.
- ADR-0006 — Bounded contexts; `local_persistence` owns the storage root.
- ADR-0010 — Base persistence decision; GRDB, WAL, Keychain rules
  carry forward unchanged.
- ADR-0011 — `PersistenceActor` is the sole writer to `storage.sqlite3`.
- ADR-0025 — `ClusterSessionActor` owns per-cluster JSON files under
  `clusters/<clusterId>/`.
