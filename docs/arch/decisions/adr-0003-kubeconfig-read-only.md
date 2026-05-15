# ADR-0003 — Kubeconfig is read-only; no credential persistence

- Status — Accepted (ratified 2026-05-15)
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — security, credentials, kubeconfig, scope

> **Scope note (2026-05-15).** This ADR is authoritative for kubeconfig material and Kubernetes API
> credentials. It is **not** authoritative for LLM API keys, which are out of scope for the original
> kubeconfig read-only decision. LLM API keys are persisted to macOS Keychain under ADR-0010;
> kubeconfig and all derived Kubernetes credentials remain read-only with no application-managed
> copy.

## Context and problem statement

K8sManager runs as a single-user macOS desktop application (ADR-0001). The MVP scope is
multi-cluster connectivity and context switching. Kubernetes credentials are sensitive — kubeconfig
files routinely contain client certificates, bearer tokens, or exec-plugin references that grant
broad cluster privileges.

We must decide whether the application: (a) treats existing kubeconfig files as the authoritative
credential store and never mutates them, or (b) imports kubeconfig contents into an
application-managed credential store (Keychain, encrypted SQLite, etc.) and possibly mutates the
on-disk kubeconfig, or (c) issues its own service-account tokens against connected clusters and
stores them locally.

This decision sets the security perimeter, the threat model, and a large portion of the
implementation surface.

## Decision drivers

- **Principle of least surprise** — operators already manage kubeconfigs with `kubectl`, `aws`,
  `gcloud`, `kubelogin`; the application should fit that workflow rather than fight it.
- **Smallest possible secret blast radius** — fewer copies of a secret is always better; importing
  tokens into a second store doubles the attack surface.
- **No write privileges required** — read-only access to `~/.kube/config` (and any file referenced
  by `KUBECONFIG`) is enough to satisfy the MVP scope.
- **Auditability** — the user can always inspect what the application reads by running
  `cat ~/.kube/config`. No invisible state.
- **No server-side rights creep** — the application should not create RBAC bindings, service
  accounts, or cluster-scoped resources without explicit user opt-in.

## Considered options

- **Option A** — Read kubeconfig only; never write; never persist credentials inside the
  application.
- **Option B** — Import kubeconfig into Keychain; lock the imported copy; mutate the on-disk
  kubeconfig to remove redundant entries.
- **Option C** — Treat the application as a kubeconfig editor; allow add, remove, rename, and merge
  of context entries on disk.

## Decision outcome

Chosen option — **Option A**, because it minimises the credential attack surface, keeps the
application aligned with existing operator workflows, and is sufficient for the MVP scope.

### Behaviour

- The application **reads** the file referenced by `KUBECONFIG`, falling back to `~/.kube/config` if
  unset, and any colon-separated additional paths listed in `KUBECONFIG` per the Kubernetes
  documentation.
- The application **never writes** to a kubeconfig file. Settings such as "last used context" and
  "pinned contexts" live in `UserDefaults` keyed by the absolute, resolved path of the source file
  plus its `mtime` to detect external edits.
- The application **does not copy credentials** into Keychain, into the application bundle, or onto
  disk in any form other than the original source file. Bearer tokens, client certs, and exec-plugin
  output are held in memory for the duration of an active connection only.
- Exec-plugin invocations (see ADR-0002) inherit the user's PATH and environment; their stdout is
  parsed in-memory and discarded after the derived credential is consumed by the HTTP client.
- The application **never modifies the cluster** — no service-account creation, no RBAC mutation, no
  resource writes. This restriction is scoped to the MVP and may be revisited in a future ADR when
  write operations (apply, scale, exec) enter the product.

### Consequences

- **Positive** — minimal secret blast radius; aligned with user expectations; no Keychain
  entitlement required; no kubeconfig corruption risk; trivially uninstallable (the application
  keeps zero state about credentials).
- **Negative** — features that require persisting derived state per cluster (e.g., custom display
  names) must key off the source-file context name and tolerate context renames; some convenience
  features (e.g., one-click kubeconfig merge) are out of scope.
- **Neutral** — telemetry, if ever introduced, must never include cluster names, token fingerprints,
  or hostnames without explicit opt-in (separate ADR).

### Confirmation

- A filesystem audit of the application's sandbox-equivalent state
  (`~/Library/Application Support/com.archanjo.K8sManager`,
  `~/Library/Preferences/com.archanjo.K8sManager.plist`,
  `~/Library/Containers/com.archanjo.K8sManager`) reveals no copy of any kubeconfig file or
  credential.
- A grep for `kSecClass` and related Keychain APIs in the codebase returns no calls.
- An integration test deletes the source kubeconfig while the application is running; the open
  connections fail closed without leaking credentials to disk.

## Pros and cons of the options

### Option A — Read-only kubeconfig

- **Pros** — minimal attack surface; no credential duplication; matches the conventional operator
  workflow; trivial to reason about.
- **Cons** — application cannot offer kubeconfig editing as a feature (only viewing); some advanced
  features (cluster favourites with rich metadata) require external storage.

### Option B — Import into Keychain

- **Pros** — Keychain offers OS-managed encryption; granular access control per-application.
- **Cons** — doubles the credential store; user must trust the application's import logic; key
  rotation in exec-plugin clusters becomes a synchronisation problem; revoked tokens persist in
  Keychain until manually cleared.

### Option C — Kubeconfig editor

- **Pros** — user-facing value (merge, rename, prune) is real.
- **Cons** — writing to a file shared with `kubectl`, `aws`, `gcloud`, and others is a
  race-condition magnet; backup responsibility shifts to the application; out of MVP scope.

## More information

- ADR-0001 — macOS-native runtime.
- ADR-0002 — SwiftkubeClient adapter (must not require credential persistence).
- Threat model and entitlements declarations to be captured in a forthcoming policy under
  `contexts/cluster_connectivity/policies/`.
