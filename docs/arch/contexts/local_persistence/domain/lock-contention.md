# Lock-Contention Analysis — `local_persistence`

Reference: ADR-0010 (local-persistence-sqlite-keychain), ADR-0011 (swift-concurrency-conventions),
ADR-0025 (per-cluster-isolation-strategy).

## Model summary

The database is opened with `PRAGMA journal_mode=WAL`. One `PersistenceActor` (ADR-0011) holds a
single read-write connection. An arbitrary number of read-only connections may be opened by other
actors using `dbQueue.read { ... }` or `DatabasePool` reader slots.

Under WAL mode SQLite allows readers and writers to proceed concurrently without blocking each other
in normal operation. Readers see a consistent snapshot of the database at the moment they begin; the
writer appends new frames to the WAL file without touching existing database pages. A checkpoint
periodically folds completed WAL frames back into the main database file.

## PRAGMA settings and their contention implications

`PRAGMA busy_timeout=5000`

When a writer is active and another writer attempts to acquire the write lock, the second writer
spins for up to 5 000 ms before returning `SQLITE_BUSY` to the GRDB layer. Because this application
has exactly one writer (`PersistenceActor`), write-vs-write contention cannot occur in production.
The timeout is defensive: it guards against a misbehaving process that opens the file in read-write
mode from outside the application (e.g., a debugging sqlite3 shell session). If `SQLITE_BUSY` is
received, `PersistenceActor` logs the event and retries once after a 500 ms delay before surfacing
the error to the caller.

`PRAGMA synchronous=NORMAL`

Durability trade-off: WAL frames are written synchronously to the OS page cache but not fsync-ed on
every write. A power failure between a write and the next checkpoint could lose the last uncommitted
transaction. This risk is acceptable for chat history and cache rows; it is NOT acceptable for
`cluster_mutation_audit`, which is why that table's INSERT path calls
`db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")` after each commit to encourage prompt flushing.

`PRAGMA wal_autocheckpoint=1000`

The WAL file is checkpointed automatically when it grows beyond 1 000 frames (roughly 4 MiB at 4 KiB
pages). During a checkpoint SQLite acquires a shared lock on the database. Readers that hold an open
snapshot prevent a full checkpoint from completing (they block the `RESTART` and `TRUNCATE`
checkpoint modes, not the `PASSIVE` mode). `PASSIVE` checkpointing — the default — writes as many
frames as possible without waiting for readers to release their snapshots.

`PRAGMA cache_size=-65536`

Approximately 64 MiB of page cache per connection. Read-only connections opened by other actors each
carry their own cache budget; the total in-process page cache can reach 64 MiB × (1 write + N read
connections). For typical usage with two to four concurrent read connections, peak cache usage is
under 320 MiB.

## Risk surfaces

**Risk 1 — Long-held read snapshots prevent WAL checkpoint.**

A read connection that issues a `BEGIN` (or stays open across multiple `read { }` blocks in GRDB
without releasing) holds its WAL snapshot. If the snapshot is older than the current checkpoint
position, the WAL file cannot be truncated past that frame. Over time the WAL file grows without
bound.

Mitigation: every read operation in the application uses GRDB's `dbQueue.read { ... }` pattern,
which wraps the read block in a deferred transaction that is released immediately on return. Long-
lived streaming queries use `DatabasePool` reader slots which are returned to the pool after each
query completes. No application code retains a `Database` handle across `await` suspension points.

**Risk 2 — Burst writes to `cluster_mutation_audit` during mutation flows.**

During a multi-step mutation (apply → watch → confirm), the audit table receives two or three
INSERTs in rapid succession. Each INSERT fires the `cluster_mutation_audit_chain_check` trigger,
which executes a `COUNT(*)` subquery on the table. On a large audit table this subquery could
degrade from O(1) to O(n) if SQLite cannot satisfy it from the page cache.

Mitigation: the `(cluster_id, requested_at)` index does not cover the `COUNT(*)` path. A dedicated
`rowid`-based count approach is preferred; alternatively, the chain-check trigger may be replaced by
an application- layer assertion in `ChainVerifier` that reads only the latest row's
`previous_entry_digest` by primary key lookup. The trigger remains as a structural guard, not a
performance-critical path.

**Risk 3 — `editor_drafts_prune` trigger on every auto-save.**

`DraftAutoSaver` inserts a row every 5 seconds while a buffer is dirty. Each INSERT fires the
`editor_drafts_prune` trigger, which issues a
`DELETE ... WHERE saved_at < datetime('now', '-24 hours') AND editor_session_id NOT IN (...)`. The
NOT IN subquery scans the table.

Mitigation: the `(editor_session_id, saved_at)` index on `editor_drafts` allows the subquery to
resolve efficiently by scanning the index rather than the full table. On typical usage (one or two
open editor sessions, dozens of draft rows per session per day) the pruning DELETE touches at most a
few hundred rows per trigger invocation.

**Risk 4 — `mcp_wire_log` growth during long chat sessions.**

The MCP wire log records every inbound and outbound MCP frame. A long chat session with heavy tool
use can generate hundreds of frames per minute. Each row stores up to 256 KiB of redacted payload.

Mitigation: storage growth is bounded per-row at 256 KiB by the application layer before the INSERT.
Rows are deleted via `cascade` when the owning `chat_sessions` row is deleted or archived. The
`(session_id, created_at)` index supports efficient bulk-delete of all rows for a given session.

## Concurrency test targets

The following targets define the minimum acceptable performance for the production configuration
(`busy_timeout=5000`, WAL, 4 KiB pages, `wal_autocheckpoint=1000`):

- 8 concurrent read-only connections each issuing 50 sequential `SELECT` queries against
  `chat_messages` while 1 writer issues 100 INSERTs per second into `editor_drafts`: p99 read
  latency must remain below 50 ms.

- WAL file size must not exceed 8 MiB (2 000 frames) under the above burst for 60 seconds, assuming
  `wal_autocheckpoint=1000` fires.

- Checkpoint frequency: at least one `PASSIVE` checkpoint completes per 30 seconds under sustained
  100 writes/sec load.

These targets are validated by the `PersistenceActorConcurrencyTests` test suite, which uses an
on-disk temporary database (not `:memory:`) to exercise WAL file semantics.

## Recommendations

- Keep writes short. Batch large inserts into chunks of 500 rows per transaction to bound lock hold
  time.

- Avoid retaining `Database` handles across `await` suspension points. GRDB's `read { }` /
  `write { }` closures are the correct scope.

- Run `PRAGMA optimize` on each application launch (before presenting UI) to refresh query planner
  statistics without blocking the main thread. This call is fast (microseconds) on a small schema.

- Run `VACUUM INTO` weekly to produce a defragmented snapshot suitable for backup and to reclaim
  free pages from the main file. Schedule this task in the background vacuum routine defined by
  ADR-0010.
