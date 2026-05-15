# ADR-0004 — Distribution via Developer ID and notarization

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — distribution, packaging, code-signing, notarization

## Context and problem statement

K8sManager is a macOS-native application (ADR-0001) that reads
kubeconfigs (ADR-0003) and shells out to exec-plugin binaries
(ADR-0002). It needs a distribution channel that satisfies four
requirements:

- macOS Gatekeeper trusts the application on a clean install without
  the user toggling `xattr -d com.apple.quarantine` or right-clicking
  "Open".
- The application can read files outside its container (e.g.
  `~/.kube/config`) without triggering a sandbox prompt for every
  context.
- The application can spawn helper binaries (`aws`, `gcloud`,
  `kubelogin`) that live in the user's PATH.
- Releases can ship without a Mac App Store review queue blocking
  iteration speed for a single-maintainer MVP.

## Decision drivers

- **Capability fit** — the App Store sandbox would force
  security-scoped bookmarks for kubeconfig access and forbid spawning
  arbitrary helper binaries; both are deal-breakers.
- **Release velocity** — App Store review (1–7 days) does not fit the
  pace of an MVP.
- **User trust** — Gatekeeper friction discourages adoption; the
  application must be Developer ID signed and Apple-notarized.
- **Auto-update** — operators expect either Sparkle-style auto-update
  or a Homebrew Cask channel; both must integrate with the chosen
  packaging.

## Considered options

- **Option A** — Direct download, Developer ID signed,
  notarized via `notarytool`, distributed as a notarized DMG and
  optional Homebrew Cask.
- **Option B** — Mac App Store (sandboxed, hardened runtime).
- **Option C** — Ad-hoc signed `.app` distributed via a public website
  with no notarization; users bypass Gatekeeper manually.
- **Option D** — Open-source-only via Homebrew tap with self-built
  binary; no signing.

## Decision outcome

Chosen option — **Option A (Developer ID + notarization)**, because it
is the only option that delivers Gatekeeper trust **without** the
sandbox restrictions that would block reading user kubeconfigs and
spawning auth-plugin binaries.

### Behaviour

- Build artefact is a `.app` bundle inside a `.dmg`, signed with the
  Developer ID Application certificate associated with the
  `com.archanjo.K8sManager` bundle identifier.
- The application enables **Hardened Runtime** with explicit
  exceptions only as needed (initially: `com.apple.security.cs.allow-jit`
  is **not** required; `com.apple.security.cs.disable-library-validation`
  is **not** required; `com.apple.security.inherit` is **not**
  required). The exec-plugin port spawns out-of-process via
  `Foundation.Process`, which is permitted under Hardened Runtime
  without entitlement waivers.
- Notarization is performed via `xcrun notarytool submit ... --wait`
  in CI; the DMG is then stapled with `xcrun stapler staple`.
- Auto-update channel — Sparkle, with the appcast hosted on a
  static endpoint (GitHub Pages or equivalent). Signing key for
  Sparkle's `EdDSA` channel is rotated annually.
- Secondary distribution channel — a Homebrew Cask formula that
  downloads the stapled DMG and forwards the same signed binary.

### Consequences

- **Positive** — no sandbox friction; no App Store review; Gatekeeper
  green on first launch; auto-update is straightforward.
- **Negative** — requires an active Apple Developer Program enrolment
  ($99/year) and a Developer ID Application certificate; notarization
  adds one to fifteen minutes to release time; Sparkle introduces a
  third-party dependency with its own security surface.
- **Neutral** — App Store distribution remains a future option once
  the sandbox-restricted feature set is acceptable.

### Confirmation

- A clean macOS 14 virtual machine launches the downloaded DMG, drags
  the `.app` into Applications, opens it, and Gatekeeper does not
  display a quarantine warning.
- `spctl --assess --verbose=4 /Applications/K8sManager.app` reports
  `accepted` and `source=Notarized Developer ID`.
- `codesign --verify --deep --strict /Applications/K8sManager.app`
  exits 0.
- `stapler validate /Applications/K8sManager.app` reports the staple
  is present and valid.

## Pros and cons of the options

### Option A — Developer ID + notarization

- **Pros** — full filesystem and subprocess access; no review queue;
  Gatekeeper trusted; integrates with Sparkle and Homebrew Cask.
- **Cons** — $99/year developer enrolment; manual or automated
  notarization step; signing-key management.

### Option B — Mac App Store

- **Pros** — discoverability; managed updates; user payment plumbing.
- **Cons** — sandbox prevents arbitrary kubeconfig access and exec
  plugins; review queue; in-app purchase rules; no Sparkle.

### Option C — Ad-hoc signed, no notarization

- **Pros** — zero infrastructure cost.
- **Cons** — Gatekeeper warning on first launch; users must
  `xattr -d com.apple.quarantine`; smell of an untrusted application.

### Option D — Homebrew tap with unsigned binary

- **Pros** — minimal infrastructure.
- **Cons** — Gatekeeper rejects unsigned binaries by default; users
  must manually allow execution; not acceptable for a polished product.

## More information

- ADR-0001 — macOS runtime choice (depends on this).
- ADR-0003 — Read-only kubeconfig (compatible with sandbox-free
  distribution).
- Future ADR — telemetry and crash reporting, which interact with
  Apple's privacy review even outside the App Store.
