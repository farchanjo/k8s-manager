# Migration Policy — `local_persistence`

Reference: ADR-0010 (local-persistence-sqlite-keychain).

## Core rules

Migrations are **append-only and forward-only**. Every schema change is expressed as a new numbered
migration function. No migration is ever modified after it is merged. Down-migration is not
supported; operators who need to roll back restore from a pre-upgrade backup.

## Naming convention

Each migration is a Swift static function with the signature:

```swift
static func v<N>_<description>(db: Database) throws
```

where `<N>` is the monotonically increasing integer matching the row inserted into
`schema_migrations`, and `<description>` is a snake_case label summarising the change, for example:

```
v1_initial_schema
v2_cluster_mutation_audit
v3_editor_drafts
v4_mcp_wire_log
v5_trusted_exec_plugins
```

## Registration with GRDB

Every migration is registered in the application's single `DatabaseMigrator` instance in strict
numeric order:

```swift
var migrator = DatabaseMigrator()
migrator.registerMigration("v1_initial_schema", migrate: Migration.v1_initial_schema)
migrator.registerMigration("v2_cluster_mutation_audit", migrate: Migration.v2_cluster_mutation_audit)
// ... additional migrations appended here in order
try migrator.migrate(dbQueue)
```

GRDB's `DatabaseMigrator` records applied identifiers in its own internal table (`grdb_migrations`)
in addition to the application's `schema_migrations` row. Both must agree; a mismatch is treated as
a fatal startup error.

## Transaction contract

Every migration body executes inside the transaction that GRDB opens automatically. The
`schema_migrations` insert happens within the same transaction as the DDL changes. If the migration
function throws, the transaction is rolled back and the process exits with a descriptive error.

```swift
static func v1_initial_schema(db: Database) throws {
    try db.create(table: "schema_migrations") { t in
        t.column("version", .integer).primaryKey()
        t.column("applied_at", .text).notNull()
        t.column("description", .text).notNull()
    }
    // ... other CREATE TABLE statements
    try db.execute(sql: """
        INSERT INTO schema_migrations (version, applied_at, description)
        VALUES (1, '\(ISO8601DateFormatter().string(from: Date()))', 'v1_initial_schema')
    """)
}
```

## Index creation

Indexes are created inside the migration that introduces the corresponding table or column. Index
names use the pattern `idx_<table>_<columns>` and match the names declared in `storage.dbml`.

## Trigger creation

SQLite triggers that enforce append-only semantics and automatic pruning (see
`policies/audit-trigger.sql`) are created in the migration that introduces the corresponding table.
They are idempotent (`CREATE TRIGGER IF NOT EXISTS`) so they survive a re-run on a fresh database
during testing.

## Down-migration

Not supported. There is no `revertMigration` path. Forward-only design eliminates an entire class of
migration-state divergence issues. Operators requiring rollback must restore the SQLite file from a
pre-upgrade backup taken via the SQLite Backup API (see `domain/backup-restore.md`).

## Testing policy

Every migration must pass the following test suite before merge:

- **Sequential migration test.** Apply all registered migrations in order on a fresh in-memory
  database opened with `DatabaseQueue(path: ":memory:")`. Assert that the final
  `schema_migrations.version` equals the highest registered migration number.

- **Schema integrity check.** After full migration, call `db.execute(sql: "PRAGMA integrity_check")`
  and assert the result is `"ok"`.

- **Foreign key check.** After full migration, call `db.execute(sql: "PRAGMA foreign_key_check")`
  and assert zero rows are returned.

- **Idempotency check.** Run the migrator a second time on the already- migrated database and assert
  no additional rows appear in `schema_migrations`.

- **Individual migration isolation test.** Each migration function is called directly on a database
  that contains exactly the state produced by all prior migrations. This catches regressions
  introduced by out-of-order DDL.

## Schema inspection

To inspect the current schema on a live database:

```
sqlite3 ~/.config/k8smanager/storage.sqlite3 .schema
```

To check which migrations have been applied:

```
sqlite3 ~/.config/k8smanager/storage.sqlite3 \
  "SELECT version, applied_at, description FROM schema_migrations ORDER BY version;"
```

## Sensitive column guidance

A migration that adds a column intended to hold user-visible content must also update the redaction
policy (`policies/secret_redaction.rego`) to ensure the new column is evaluated before writes
commit. Columns that will never hold user text (e.g., digest fields, boolean flags, timestamps) are
exempt from this requirement, but a comment in the migration must state the rationale explicitly.
