// DDD role: DomainService
package local_persistence

// persistence_store.cue — Aggregate root representing the single durable
// SQLite WAL store managed by the local_persistence bounded context.
//
// This file declares:
//   #PersistenceStore     — the aggregate root (the physical store).
//   #PersistenceMigration — entity recording individual schema migrations.
//
// Port commentary
// ===============
// The ports listed below are declared in the domain core and consumed by
// the bounded contexts shown. Their persistence implementations (SQLite
// repository adapters) all write to the same #PersistenceStore instance.
//
//   ChatRepositoryPort           — owned by chat_session context.
//                                  Persists chat_sessions and chat_messages.
//
//   ProviderRepositoryPort       — owned by provider_config context.
//                                  Persists provider_profiles and
//                                  provider_capabilities.
//
//   ClusterAnalysisCachePort     — owned by cluster_connectivity context.
//                                  Persists cluster_analysis_cache rows.
//
//   OperatorPreferencesPort      — owned by settings context.
//                                  Persists operator_preferences key-values.
//
//   MCPInvocationLogPort         — owned by mcp_integration context.
//                                  Persists mcp_invocations rows.
//
//   ClusterMutationAuditPort     — owned by resource_browser context.
//                                  Persists cluster_mutation_audit rows.
//                                  Added in ADR-0012; table is append-only.
//
//   LLMKeyStorePort              — owned by provider_config context.
//                                  Reads/writes Keychain entries via the
//                                  Security framework; does NOT write to
//                                  SQLite. Declared here for completeness
//                                  because all other provider persistence
//                                  flows through this aggregate root.

// UUIDv7 pattern used across identity fields.
#_UUIDv7: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

// #PersistenceStore is the aggregate root for the local SQLite database.
// The application maintains exactly one instance of this aggregate per
// process; it is initialised at launch and torn down at clean exit.
//
// Physical path:
//   ~/Library/Application Support/com.archanjo.K8sManager/storage.sqlite3
//
// PRAGMAs applied after every connection open:
//   PRAGMA journal_mode=WAL;
//   PRAGMA synchronous=NORMAL;
//   PRAGMA foreign_keys=ON;
//   PRAGMA busy_timeout=5000;
//   PRAGMA cache_size=-65536;
#PersistenceStore: {
	// id is the UUIDv7 generated at first launch and persisted in the
	// operator_preferences table under key "store.aggregate_id". It
	// survives app restarts and is used as a stable identity for this
	// specific SQLite file on disk.
	id!: #_UUIDv7

	// storageFilePath is the absolute POSIX path to the SQLite file.
	// Must begin with "/" (no relative paths, no UNC paths).
	storageFilePath!: =~"^/.+"

	// journalMode is locked to WAL for the K8sManager store. Any
	// migration that attempts to change this value is a logic error.
	journalMode: "wal"

	// schemaVersion is the current applied migration version, read from
	// the schema_migrations table at startup. Must be >= 1 after the
	// baseline migration has run.
	schemaVersion!: int & >=1

	// lastVacuumAtRFC3339 records when the most recent VACUUM was run.
	// Optional; absent until the first scheduled vacuum executes.
	lastVacuumAtRFC3339?: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" | null
}

// #PersistenceMigration is an entity that records a single applied schema
// migration. Rows in the schema_migrations SQLite table are the persistence
// projection of this entity. Migrations are numbered strictly from 1 and
// applied in ascending order; gaps in the sequence are treated as errors
// by the migration runner.
#PersistenceMigration: {
	// version is the monotonically increasing migration number (1, 2, 3 …).
	// There are no gaps; the migration runner rejects out-of-sequence applies.
	version!: int & >=1

	// appliedAtRFC3339 is the UTC RFC3339 timestamp at which the migration
	// SQL was executed successfully.
	appliedAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"

	// description is a short human-readable summary of what the migration
	// changes. Persisted in the schema_migrations.description column for
	// operational visibility.
	description!: string & !=""

	// checksumSHA256 is the SHA-256 hex digest of the migration SQL file
	// content. The migration runner validates this on every startup to
	// detect tampering with already-applied migrations.
	checksumSHA256!: =~"^[0-9a-f]{64}$"
}
