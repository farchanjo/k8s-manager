# ADR-0047 — Audit chain HMAC-SHA256 with Keychain-stored key

- Status — Accepted (ratified 2026-05-15)
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none)
- Informed — (none)
- Tags — audit, security, hmac, keychain, local_persistence, resource_browser
- Refines — ADR-0010 (local-persistence-sqlite-keychain)
- Refines — ADR-0012 (mutating-operations-policy)

## Context and problem statement

The audit chain in `mutation_audit_entry.cue:82-93` specifies that `previousEntryDigest` is a
SHA-256 hex digest. The Gherkin scenario
`docs/arch/contexts/resource_browser/features/chaos/audit-log-tamper-detected.feature:13` already
uses the term "HMAC" in its `Background:` step, but no ADR or schema formalises the key-management
model. The existing plain SHA-256 hash is publicly computable: an adversary who can write to the
SQLite file can recompute the chain over modified rows and replace every digest, defeating tamper
detection entirely. The threat model requires that chain verification be key-gated so that
recomputation is computationally infeasible without the secret key.

The gap was identified in a security audit cross-referencing `mutation_audit_entry.cue` (lines
82–93) against the Gherkin scenario. The feature file promises HMAC semantics; the schema delivers
plain SHA-256. This ADR closes that discrepancy.

## Decision drivers

- **Tamper evidence** — an adversary with local filesystem write access must not be able to silently
  repair a modified audit chain.
- **Key confidentiality** — the verification key must not be accessible to the same threat actor
  that can write to the SQLite file; therefore the key must live outside the database.
- **macOS-native key management** — consistent with ADR-0010, Keychain is the designated secret
  store; no third-party key management dependency is introduced.
- **Zero additional infrastructure** — the solution must work with the existing GRDB stack and macOS
  Security framework; no network-accessible HSM or KMS is needed.
- **Failure graceful** — Keychain unavailability (locked device, Keychain wipe) must produce a
  clearly surfaced degraded state, not a silent audit gap.

## Considered options

1. **Plain SHA-256 (status quo)** — retain the existing hash chain. Accepts the gap: an adversary
   with write access can recompute the chain and conceal tampering.
2. **HMAC-SHA256 with Keychain-stored key** — generate a 256-bit random key on first launch, store
   it in macOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and compute each
   entry's digest as `HMAC-SHA256(key, previousEntryDigest || canonicalEntryJSON)`.
3. **Ed25519 per-entry signatures** — generate an Ed25519 signing key, store the private key in
   Keychain, and sign each canonical entry JSON independently.
4. **Append-only Apple log API (`os_log` unified logging)** — delegate audit to Apple's unified
   logging subsystem, which is managed by logd and resistant to user-level tampering.

## Pros and cons of the options

### Option 1 — Plain SHA-256 (status quo)

- Pro: no key management complexity.
- Pro: verification requires no Keychain access.
- Con: an adversary with filesystem write can recompute the entire chain after modification,
  defeating tamper evidence.
- Con: already inconsistent with the Gherkin scenario wording ("HMAC"), creating a documented
  specification gap.

### Option 2 — HMAC-SHA256 with Keychain-stored key

- Pro: recomputation of the chain is infeasible without the key; Keychain separation puts the key
  outside the threat actor's reach for a filesystem-only attack.
- Pro: uses existing macOS Keychain integration from ADR-0010; no new dependency.
- Pro: low algorithmic overhead — one HMAC-SHA256 call per audit write; negligible compared to the
  SQLite WAL commit cost.
- Con: Keychain wipe or migration to a new device invalidates prior chain; must define a
  well-specified degraded mode.
- Con: key rotation is non-trivial because all prior digests are bound to the key; rotation is
  deferred to v2 (see More Information).

### Option 3 — Ed25519 per-entry signatures

- Pro: asymmetric scheme allows external parties to verify entries using the public key without
  access to the signing key.
- Con: significantly higher key management complexity (certificate lifecycle, public key
  distribution, revocation).
- Con: Ed25519 signature size (64 bytes) stored per row increases table footprint more than a
  32-byte HMAC.
- Con: no identified requirement for external third-party verification of the audit log; the
  asymmetric benefit is speculative.
- Neutral: could be revisited if enterprise audit export to a SIEM with cryptographic verification
  becomes a requirement.

### Option 4 — Append-only Apple log API

- Pro: tamper resistance is handled by logd at OS level; no application-level key management.
- Con: logd entries are not queryable with SQL; the existing audit UI (timeline widget, export)
  would require a complete rewrite.
- Con: logd retention policies are controlled by the OS, not the application; entries can be pruned
  before the operator reviews them.
- Con: the audit export feature (CSV, forensic review) cannot source from logd in a structured way.
- Con: completely incompatible with the existing `cluster_mutation_audit` SQLite table and all
  downstream consumers.

## Decision outcome

**Chosen option: 2 — HMAC-SHA256 with Keychain-stored key.**

Rationale: it closes the tamper-evidence gap with minimal architectural change, reuses the
established Keychain integration from ADR-0010, and is consistent with the existing Gherkin scenario
wording. The failure mode (Keychain unavailable) is well-defined and consistent with the pattern
established for LLM key storage.

### Specification

**Key generation and storage:**

- Actor: `AuditChainKeyManager` (DomainService in `local_persistence`).
- Key: 256-bit (32 bytes) random data generated via `SecRandomCopyBytes`.
- Storage: macOS Keychain item with the following attributes:
  - `kSecClass`: `kSecClassGenericPassword`
  - `kSecAttrService`: `com.archanjo.K8sManager.audit`
  - `kSecAttrAccount`: `chain-mac-key-v1`
  - `kSecAttrAccessible`: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  - `kSecAttrLabel`: `"K8sManager audit chain MAC key"`
- The key is generated once on first launch and never regenerated automatically. If the key item is
  absent (fresh install, Keychain wipe, new device migration), `AuditChainKeyManager` generates a
  new key, stores it, and records the event in the diagnostics log.

**Per-entry digest:**

```
entryDigest = HMAC-SHA256(key, previousEntryDigest_hex || canonicalEntryJSON_utf8)
```

- `previousEntryDigest_hex` is the 64-character lowercase hex string of the preceding entry's
  `entryDigest` (or `"0" * 64` for the genesis row).
- `canonicalEntryJSON_utf8` is the UTF-8 JSON serialisation of all `#MutationAuditEntry` fields in
  schema-defined order, excluding `previousEntryDigest` and `entryDigest` themselves.
- The resulting HMAC is stored as a 64-character lowercase hex string.

**Genesis row:**

- `previousEntryDigest` is the sentinel `"0" * 64` (64 zero hex characters).
- The trigger in `audit-trigger.sql` already enforces this structural invariant for empty tables; it
  is unchanged (the trigger cannot verify HMAC — that remains an application-layer concern).

**Key version tracking:**

- Each `#MutationAuditEntry` carries a `keyVersion` field (default `"v1"`). If key rotation is
  implemented in a future version, entries produced with the old key carry the prior version tag so
  that the verifier knows which key to use.

**Verification:**

- `ChainVerifier` actor checks on: (a) app launch, (b) each mutation write (verify the immediately
  preceding entry only), and (c) `spec validate --lane audit`.
- If HMAC verification fails on any entry, the chain is marked corrupt and new writes are suspended
  (consistent with the existing scenario in `audit-log-tamper-detected.feature`).

**Key unavailability:**

- If the Keychain is locked at verification time, the chain is paused (not marked corrupt). The UI
  surfaces "Audit chain paused — Keychain locked. Unlock to resume verification."
- If the Keychain item is absent (possible after a Keychain wipe or device migration), the audit
  chain is marked corrupt for the prior entries (which cannot be re-verified). The sequence number
  resets to 0, a new genesis entry is written with the freshly generated key, and prior entries
  remain readable for forensic review but their HMAC tags are unverifiable.

**Key rotation (v1 limitation):**

- Not supported in v1. Rotating the key invalidates all existing HMAC tags. A future version may
  implement rotation by: (a) re-signing all rows under the new key, (b) bumping `keyVersion`, and
  (c) removing the old Keychain item. This ADR will be superseded when rotation is implemented.

### Consequences

- **Positive** — audit chain is now key-gated; filesystem-only adversaries cannot silently repair a
  tampered chain; closes the specification gap between the schema and the Gherkin scenario.
- **Positive** — no new dependency; uses existing Security framework and GRDB stack.
- **Negative** — Keychain wipe (Keychain reset, device migration, new Mac) renders prior audit
  entries unverifiable; the application surfaces this as a degraded state.
- **Negative** — key rotation is not supported in v1; a Keychain wipe is the only "rotation path"
  and it breaks prior chain verification.
- **Neutral** — the SQLite trigger in `audit-trigger.sql` retains structural integrity enforcement
  (genesis check, non-empty chain check) but cannot verify the HMAC itself; HMAC verification
  remains an application-layer concern.

### Confirmation

- Unit test: `ChainVerifier` correctly verifies a 100-entry chain built with the test HMAC key.
- Unit test: `ChainVerifier` rejects a chain where entry #48 has a tampered `canonicalEntryJSON`.
- Unit test: `AuditChainKeyManager` generates a key, stores it in Keychain, and retrieves it on a
  simulated second launch without regenerating.
- Integration test: Keychain locked → audit verification pauses; Keychain unlocked → verification
  resumes.
- Integration test: Keychain item deleted → chain marked corrupt; new genesis entry created with new
  key; prior entries remain readable.
- Spec lane: `spec validate --lane audit` walks all rows and reports any HMAC mismatch.

## More information

- ADR-0010 — Local persistence SQLite and Keychain (key storage pattern and access control
  attributes).
- ADR-0012 — Mutating operations policy (audit log write contract).
- Schema updated: `docs/arch/contexts/resource_browser/schemas/mutation_audit_entry.cue` (lines
  82–93 semantics, added `keyVersion` field).
- Schema updated: `docs/arch/contexts/local_persistence/schemas/keychain_entry.cue` — see companion
  `docs/arch/contexts/local_persistence/schemas/audit_chain_key.cue` for the new key entry shape.
- Trigger updated: `docs/arch/contexts/local_persistence/policies/audit-trigger.sql` (lines 60–73 —
  comment clarification; trigger logic unchanged).
- Gherkin updated:
  `docs/arch/contexts/resource_browser/features/chaos/audit-log-tamper-detected.feature` — added
  three scenarios: HMAC key missing, HMAC verify fail, Keychain locked at verification.
- Key rotation design: deferred to ADR-0047-v2 (not yet created).
