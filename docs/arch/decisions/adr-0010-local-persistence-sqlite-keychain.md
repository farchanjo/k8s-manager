# ADR-0010 — Local persistence — SQLite for non-secret state, macOS Keychain for LLM API keys

- Status — Proposed; driver library pinned by ADR-0019
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — persistence, sqlite, keychain, secrets, storage

> **Pinning note (2026-05-15).** The SQLite Swift driver is pinned to
> **`groue/GRDB.swift`** version 7.10.x (Swift 6.1+ obligatory) per
> ADR-0019. Schema additions for mutating-operation audit
> (`cluster_mutation_audit`) and any new bounded contexts introduced
> after ADR-0010 land as numbered migrations under the existing
> `schema_migrations` regime; no schema is mutated outside a migration.

## Context and problem statement

ADR-0006 introduces the `local_persistence` bounded context. The
application now needs to store:

- Chat sessions and their messages (with tool-call audit entries
  and attachment metadata).
- LLM provider profiles (URL, model, temperature, etc. — but not
  the API key value).
- Cluster-analysis cache (summaries the assistant computed for a
  cluster, used to skip recomputation on next session).
- Operator preferences (theme, sidebar layout, refresh intervals).
- LLM API keys — sensitive material that must not live alongside
  the rest.

ADR-0003 mandates that the kubeconfig is read-only and that no
Kubernetes credential is persisted by the application. That ADR's
scope is kubeconfig and Kubernetes credentials only; LLM API keys
are out of scope there and are decided here.

We must pick a storage strategy that is fast, embedded, schema-aware,
and respects platform conventions for secrets.

## Decision drivers

- **Secrets stay in Keychain** — the macOS Keychain is the platform's
  curated home for secret material; storing API keys anywhere else is
  a regression.
- **Non-secret state benefits from a relational store** — chat
  history, cluster analyses, and preferences gain from queries,
  transactions, and schema evolution.
- **WAL for concurrent readers and a single writer** — the
  application has a single writer (the persistence actor) and many
  readers (assistant, settings surface, sidebar, diagnostics);
  WAL is the natural fit.
- **No network dependency** — local-first operation is essential to
  the offline-friendly story (Ollama, LM Studio, air-gapped use).
- **Backup-friendly** — operators should be able to copy the
  database file out and back without contortions.

## Decision outcome

- The non-secret persistent state lives in a single SQLite file at
  `~/Library/Application Support/com.archanjo.K8sManager/storage.sqlite3`.
  Sidecar WAL files are permitted.
- The application opens the database with PRAGMAs:
  `journal_mode=WAL`, `synchronous=NORMAL`, `foreign_keys=ON`,
  `busy_timeout=5000`, `cache_size=-65536` (~64 MB).
- All writes go through a single `PersistenceActor` (ADR-0011).
  Readers may use additional read-only connections opened with
  `?mode=ro&immutable=0`.
- The Swift driver is **GRDB** (pure Swift, no system-bundled
  SQLite version assumptions, idiomatic Codable integration, robust
  migrations API).
- Schema migrations are append-only; each migration is a numbered
  Swift function that runs inside a transaction; the version is
  pinned in a `schema_migrations` table.
- LLM API keys are stored in the macOS Keychain via
  `kSecClassGenericPassword` with `service = "com.archanjo.K8sManager.llm"`
  and `account = "<providerProfileId>"`. The Keychain entry is
  protected by `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so
  the key never leaves the device.
- The Keychain entry is created and updated through the
  `LLMKeyStorePort` defined in `local_persistence`; the default
  adapter wraps the Security framework. The port API never returns
  the key value to code outside `llm_provider`'s adapters and never
  logs the key.
- Cluster-analysis cache rows carry an explicit
  `expiresAtRFC3339` and are pruned by a periodic vacuum task; the
  database is vacuumed weekly (`PRAGMA optimize` on launch,
  `VACUUM INTO` to a sidecar weekly).
- The SQLite file is **never** read or written by the domain core;
  all access is mediated by the persistence ports declared in
  `local_persistence`.

### Backups and reset

- A "reveal storage in Finder" affordance in settings opens the
  enclosing folder.
- A "delete local data" button clears the SQLite file and removes
  every `com.archanjo.K8sManager.llm` Keychain entry. It is
  irreversible and confirms twice.

### Consequences

- **Positive** — secrets stay in Keychain (platform-trusted);
  non-secret state benefits from queries and transactions; one
  file to back up; WAL gives concurrent read access without
  starving the writer; GRDB integrates cleanly with Swift Codable.
- **Negative** — GRDB is a third-party dependency; migrations
  require discipline (irreversible numeric ordering);
  Keychain prompts on first read can surprise the operator and
  require a UX affordance.
- **Neutral** — SQLite's `:memory:` mode is available for tests;
  GRDB exposes both throwing and async APIs.

### Confirmation

- The application stores LLM API keys in Keychain; running
  `security find-generic-password -s "com.archanjo.K8sManager.llm"`
  shows the entries.
- The SQLite file is created on first launch with the expected
  WAL journal mode (`PRAGMA journal_mode;` returns `wal`).
- A migration test executes every migration on a fresh database in
  order and asserts schema parity with the latest in-code definition.
- A negative test attempts to read the API key from the SQLite
  file and asserts the value is absent.
- A "delete local data" test removes both the SQLite file and the
  Keychain entries on confirmation.

## Considered options

### Option A — SQLite + Keychain (chosen)

- **Pros** — platform-correct split between secrets and metadata;
  fast local queries; backup is one file; GRDB is mature.
- **Cons** — two storage surfaces to back up if the user wants to
  preserve API keys (Keychain export is a separate workflow).

### Option B — SQLite + SQLCipher for secrets and metadata in one file

- **Pros** — single file holds everything.
- **Cons** — SQLCipher requires master-key management; Apple users
  rightly expect Keychain for secrets; conflicts with platform
  norms.

### Option C — JSON or property-list files plus Keychain

- **Pros** — minimum dependencies.
- **Cons** — no transactions; partial writes risk corruption; no
  query story for chat history.

### Option D — Realm or Core Data

- **Pros** — Apple-native (Core Data); ergonomic (Realm).
- **Cons** — Core Data's migration ergonomics are heavy for a
  small schema; Realm has a non-standard file format and licensing
  considerations.

## More information

- ADR-0003 — Kubeconfig read-only (this ADR clarifies the LLM-key
  scope without reopening kubeconfig persistence).
- ADR-0006 — Defines the `local_persistence` bounded context.
- ADR-0008 — `ProviderProfile.keyAlias` references a Keychain
  entry written by this ADR's storage strategy.
- ADR-0011 — `PersistenceActor` lives under Swift concurrency
  conventions.
