# Backup and Restore — `local_persistence`

Reference: ADR-0010 (local-persistence-sqlite-keychain), ADR-0025 (per-cluster-isolation-strategy),
ADR-0026 (state-persistence-and-filesystem-layout).

## Storage surfaces covered by this document

The application's local state is split across three surfaces:

1. `~/.config/k8smanager/storage.sqlite3` — the SQLite database (plus sidecar WAL and SHM files
   while the application is running).

2. `~/.config/k8smanager/clusters/<clusterId>/` — per-cluster JSON files managed by
   `ClusterSessionActor` (ADR-0025).

3. macOS Keychain — LLM API keys, OIDC refresh tokens, Azure MSAL tokens under three service
   namespaces (ADR-0010 refinement note).

Each surface has its own backup and restore procedure. There is no single-click "export everything"
workflow; the Keychain is intentionally excluded from file backups because it has its own iCloud
Keychain sync mechanism that the operator controls externally.

## SQLite backup

The SQLite Backup API produces a consistent, point-in-time snapshot of the database without
acquiring a read lock that blocks the writer. The `sqlite3` CLI exposes this API via the `.backup`
dot-command:

```
sqlite3 ~/.config/k8smanager/storage.sqlite3 \
  ".backup '/path/to/backup.sqlite3'"
```

The backup command copies the main database file and replays any uncommitted WAL frames into the
backup so the snapshot is fully consistent. The original WAL sidecar files are not copied; the
backup file is a self-contained single-file database in rollback journal mode.

The application provides a "Backup now" affordance in Settings that invokes GRDB's `backup(to:)`
method, which wraps the same Backup API. The default backup location is a timestamped file in the
operating system's temporary directory; the operator is prompted to move it to a permanent location.

Scheduled backup: the weekly vacuum task appended to by ADR-0010 also invokes
`VACUUM INTO '/path/to/weekly-backup.sqlite3'` to produce a defragmented snapshot in addition to the
online backup. This is a separate file; both are valid restore sources.

## SQLite restore

Before restoring, the application must not be running. The restore procedure is:

1. Quit K8sManager completely.

2. Locate the sidecar files alongside the live database:

   ```
   ~/.config/k8smanager/storage.sqlite3
   ~/.config/k8smanager/storage.sqlite3-wal
   ~/.config/k8smanager/storage.sqlite3-shm
   ```

3. Delete all three files (the `-wal` and `-shm` sidecars must be removed to avoid confusing SQLite
   when the restored file is opened without a matching WAL).

4. Copy the backup file to `~/.config/k8smanager/storage.sqlite3`.

5. Launch K8sManager. The migration runner executes on startup and asserts that the restored file's
   schema version matches the current application's highest registered migration. If the restored
   file is from an older application version, pending migrations are applied automatically. If the
   restored file is from a newer version than the running application, the application exits with an
   error message instructing the operator to upgrade.

## Per-cluster JSON backup

The `clusters/` directory contains one subdirectory per cluster UUIDv7. Each subdirectory holds JSON
files managed atomically by `ClusterSessionActor`. To back up cluster state:

```
cp -r ~/.config/k8smanager/clusters/ /path/to/backup/clusters/
```

Restore procedure: quit the application, replace the `clusters/` directory with the backup copy,
then relaunch. The application reads the JSON files on the next `ClusterSessionActor`
initialisation.

## Keychain backup

Keychain entries created by the application are covered by iCloud Keychain synchronisation if the
operator has enabled that feature in macOS System Settings. The application writes all entries with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, which explicitly opts out of iCloud Keychain sync to
ensure keys never leave the device.

Consequence: Keychain entries are NOT included in any file backup. An operator who restores the
SQLite database onto a new machine must re-enter API keys in the provider profile settings. The
application detects missing Keychain entries on the first API call and prompts the operator to
supply the key.

Operators who wish to preserve API keys across machine migrations must use macOS Keychain Access to
export the items manually. This is outside the application's scope and is documented in the user
guide only.

## "Delete local data" procedure

The "delete local data" action available in Settings performs the following steps after two explicit
operator confirmations:

1. Close all active database connections.

2. Remove the SQLite database and its sidecar files:

   ```
   ~/.config/k8smanager/storage.sqlite3
   ~/.config/k8smanager/storage.sqlite3-wal
   ~/.config/k8smanager/storage.sqlite3-shm
   ```

3. Remove all per-cluster JSON directories:

   ```
   ~/.config/k8smanager/clusters/
   ```

4. Delete every Keychain entry under all three application service namespaces:
   - `com.archanjo.K8sManager.llm` — LLM API keys.
   - `com.archanjo.K8sManager.oidc.<clusterId>` — OIDC refresh tokens.
   - `com.archanjo.K8sManager.azure.<clusterId>` — Azure MSAL tokens.

5. Terminate and relaunch the application into the first-run onboarding flow.

The confirmation dialog states explicitly that LLM API keys, OIDC refresh tokens, and Azure cluster
sessions will all be permanently deleted. This operation is irreversible. There is no undo path.

## Backup integrity verification

After producing a backup, the operator or an automated script can verify the backup file's
integrity:

```
sqlite3 /path/to/backup.sqlite3 "PRAGMA integrity_check;"
sqlite3 /path/to/backup.sqlite3 "PRAGMA foreign_key_check;"
```

Both commands should return `ok` and zero rows respectively. A non-empty `foreign_key_check` result
indicates referential integrity violations in the backup, which may indicate a bug in the
application's delete cascade logic.
