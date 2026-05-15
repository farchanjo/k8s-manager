-- DDD role: PolicyImplementation
-- SQLite trigger definitions for the local_persistence bounded context.
-- Reference: ADR-0010 (local-persistence-sqlite-keychain), ADR-0012 (mutating-operations-policy).
--
-- These triggers are created inside the migration that introduces the
-- corresponding table (see domain/migration-policy.md). All triggers use
-- "IF NOT EXISTS" so they are safe to run on a freshly created database
-- during testing without producing duplicate-trigger errors.
--
-- Execution context:
--   These triggers execute within the SQLite transaction that wraps the
--   INSERT, UPDATE, or DELETE statement. RAISE(ABORT, ...) rolls back the
--   current statement and propagates an error to the GRDB layer, which
--   surfaces it as a Swift DatabaseError. The PersistenceActor catches
--   this error and reports it to the caller without crashing.
--
-- Security note:
--   Trigger bodies must never log or expose the values of columns that
--   could contain credential material. The error messages below are
--   static strings; no NEW.* column values are interpolated.

-- ---------------------------------------------------------------------------
-- cluster_mutation_audit — append-only enforcement
-- ---------------------------------------------------------------------------

-- Trigger 1: Prevent any UPDATE on cluster_mutation_audit.
-- Rationale: the audit log is a tamper-evident ledger. Once a row is
-- committed it must not be altered by any application code path. This
-- trigger is a last-resort guard; the PersistenceActor repository
-- implementation must not issue UPDATE statements against this table.
CREATE TRIGGER IF NOT EXISTS cluster_mutation_audit_no_update
BEFORE UPDATE ON cluster_mutation_audit
BEGIN
    SELECT RAISE(ABORT, 'cluster_mutation_audit is append-only: UPDATE is not permitted');
END;

-- Trigger 2: Prevent any DELETE on cluster_mutation_audit.
-- Rationale: same tamper-evidence requirement as above. Rows must remain
-- until the operator explicitly invokes "delete local data", at which
-- point the entire SQLite file is removed rather than individual rows.
CREATE TRIGGER IF NOT EXISTS cluster_mutation_audit_no_delete
BEFORE DELETE ON cluster_mutation_audit
BEGIN
    SELECT RAISE(ABORT, 'cluster_mutation_audit is append-only: DELETE is not permitted');
END;

-- Trigger 3: Chain-integrity guard for cluster_mutation_audit.
-- Rationale: the previous_entry_digest column forms an HMAC-SHA256 chain
-- over the audit log (ADR-0047). The application computes the HMAC digest
-- in Swift using a 256-bit key stored in the macOS Keychain
-- (service "com.archanjo.K8sManager.audit", account "chain-mac-key-v1")
-- before issuing the INSERT. This trigger enforces only the structural
-- invariant: if the table is non-empty the new row MUST NOT declare an
-- empty previous_entry_digest, and if the table is empty the new row
-- MUST declare an empty previous_entry_digest (genesis row sentinel
-- "0" * 64).
--
-- IMPORTANT: SQLite does not have a native HMAC-SHA256 function. This
-- trigger cannot cryptographically verify the HMAC tag — it only enforces
-- the presence/absence structural rule. Full cryptographic chain
-- verification (HMAC key lookup from Keychain, entry-by-entry recompute)
-- is performed exclusively by the application-layer ChainVerifier actor
-- on launch, on each mutation write, and via `spec validate --lane audit`.
CREATE TRIGGER IF NOT EXISTS cluster_mutation_audit_chain_check
BEFORE INSERT ON cluster_mutation_audit
WHEN (
    -- Genesis check: table is empty but previous_entry_digest is not empty.
    ((SELECT COUNT(*) FROM cluster_mutation_audit) = 0
     AND NEW.previous_entry_digest != '')
    OR
    -- Chain check: table is non-empty but previous_entry_digest is empty.
    ((SELECT COUNT(*) FROM cluster_mutation_audit) > 0
     AND NEW.previous_entry_digest = '')
)
BEGIN
    SELECT RAISE(ABORT, 'cluster_mutation_audit chain integrity violation: previous_entry_digest is inconsistent with table state');
END;

-- ---------------------------------------------------------------------------
-- editor_drafts — automatic 24-hour prune of orphaned drafts
-- ---------------------------------------------------------------------------

-- Trigger 4: Prune editor_drafts rows older than 24 hours whose
-- editor_session_id has no snapshot within the last 24 hours.
-- Rationale: DraftAutoSaver writes a new row every 5 seconds while a buffer
-- is dirty. Without pruning, the table grows unboundedly. The pruning
-- criterion is conservative: a draft row is only deleted if its entire
-- editor_session_id has gone quiet for 24 hours, meaning the editor session
-- is presumed closed. Active sessions are never pruned mid-edit.
--
-- Implementation note: this trigger fires AFTER each INSERT so the newly
-- inserted row is visible during the DELETE subquery. The subquery uses a
-- correlated NOT IN to retain any session_id that has at least one row
-- within the last 24 hours, which includes the row just inserted.
CREATE TRIGGER IF NOT EXISTS editor_drafts_prune
AFTER INSERT ON editor_drafts
BEGIN
    DELETE FROM editor_drafts
    WHERE saved_at < datetime('now', '-24 hours')
      AND editor_session_id NOT IN (
          SELECT DISTINCT editor_session_id
          FROM editor_drafts
          WHERE saved_at >= datetime('now', '-24 hours')
      );
END;
