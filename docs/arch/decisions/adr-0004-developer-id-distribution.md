# ADR-0004 — Distribution via Developer ID and notarization

- Status — Accepted (ratified 2026-05-15)
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — distribution, packaging, code-signing, notarization

## Context and problem statement

K8sManager is a macOS-native application (ADR-0001) that reads kubeconfigs (ADR-0003) and shells out
to exec-plugin binaries (ADR-0002). It needs a distribution channel that satisfies four
requirements:

- macOS Gatekeeper trusts the application on a clean install without the user toggling
  `xattr -d com.apple.quarantine` or right-clicking "Open".
- The application can read files outside its container (e.g. `~/.kube/config`) without triggering a
  sandbox prompt for every context.
- The application can spawn helper binaries (`aws`, `gcloud`, `kubelogin`) that live in the user's
  PATH.
- Releases can ship without a Mac App Store review queue blocking iteration speed for a
  single-maintainer MVP.

## Decision drivers

- **Capability fit** — the App Store sandbox would force security-scoped bookmarks for kubeconfig
  access and forbid spawning arbitrary helper binaries; both are deal-breakers.
- **Release velocity** — App Store review (1–7 days) does not fit the pace of an MVP.
- **User trust** — Gatekeeper friction discourages adoption; the application must be Developer ID
  signed and Apple-notarized.
- **Auto-update** — operators expect either Sparkle-style auto-update or a Homebrew Cask channel;
  both must integrate with the chosen packaging.

## Considered options

- **Option A** — Direct download, Developer ID signed, notarized via `notarytool`, distributed as a
  notarized DMG and optional Homebrew Cask.
- **Option B** — Mac App Store (sandboxed, hardened runtime).
- **Option C** — Ad-hoc signed `.app` distributed via a public website with no notarization; users
  bypass Gatekeeper manually.
- **Option D** — Open-source-only via Homebrew tap with self-built binary; no signing.

## Decision outcome

Chosen option — **Option A (Developer ID + notarization)**, because it is the only option that
delivers Gatekeeper trust **without** the sandbox restrictions that would block reading user
kubeconfigs and spawning auth-plugin binaries.

### Behaviour

- Build artefact is a `.app` bundle inside a `.dmg`, signed with the Developer ID Application
  certificate associated with the `com.archanjo.K8sManager` bundle identifier.
- The application enables **Hardened Runtime** with explicit exceptions only as needed (initially:
  `com.apple.security.cs.allow-jit` is **not** required;
  `com.apple.security.cs.disable-library-validation` is **not** required;
  `com.apple.security.inherit` is **not** required). The exec-plugin port spawns out-of-process via
  `Foundation.Process`, which is permitted under Hardened Runtime without entitlement waivers.
- Notarization is performed via `xcrun notarytool submit ... --wait` in CI; the DMG is then stapled
  with `xcrun stapler staple`.
- Auto-update channel — **Sparkle 2.6 or later** (minimum version; see Sparkle trust model below).
  The appcast is hosted on a static HTTPS endpoint (GitHub Pages or equivalent). Signing key for
  Sparkle's `EdDSA` channel is rotated annually.
- Secondary distribution channel — a Homebrew Cask formula that downloads the stapled DMG and
  forwards the same signed binary. The formula pins the SHA-256 of each published DMG in the
  `sha256:` field; unsigned or hash-mismatching downloads are rejected by Homebrew before
  installation proceeds.

### Sparkle trust model

This section documents the security decisions governing the auto-update channel (HIGH-01 finding
from the initial security audit).

**EdDSA public key embedding.** The `SUPublicEDKey` value is embedded as a build-time Swift constant
in the application source rather than in `Info.plist`. Specifically, it is declared as an internal
`let` in the `UpdateChannelConfig` module compiled into the application binary. This prevents an
attacker who gains post-notarization write access to the bundle's `Info.plist` (e.g. via a
compromised `.dmg` image) from substituting a different public key without invalidating the code
signature. The `Info.plist` key `SUPublicEDKey` MUST be absent or match the embedded constant; a
mismatch causes the updater to refuse all appcast payloads at startup.

**Minimum Sparkle version.** Sparkle 2.6 or later is required. Sparkle releases prior to 2.6 contain
known vulnerabilities in the appcast parsing and delta-update verification paths. The
`Package.resolved` file MUST NOT reference any Sparkle release before 2.6.0.

**Appcast URL pinning.** The appcast URL is an HTTPS endpoint. The application enforces:

- No HTTP fallback: the URL scheme is verified to be `https` at startup; a non-HTTPS appcast URL
  causes the updater to halt and log an error.
- No `NSAllowsArbitraryLoads` exception in `Info.plist`; the App Transport Security configuration
  for the appcast host is left at the system default (HTTPS with TLS 1.2+).
- The `URLSession` used for appcast and delta-download requests delegates to the system trust store.
  No custom certificate pinning is applied to the appcast host (pinning would break when the CDN
  rotates its TLS certificate), but `NSAllowsArbitraryLoads` remains disabled and the minimum TLS
  version is enforced by ATS.

**EdDSA private key storage policy.**

- The signing private key is generated once and stored offline on an air-gapped machine or a
  hardware security key (e.g. YubiKey with EdDSA support) that never connects to the CI/CD
  infrastructure.
- The private key is never stored in a CI secret store, cloud key manager, or repository. Signing is
  performed locally by the release engineer on the air-gapped machine, and only the signed appcast
  XML file and the DMG artifact are published.
- Key rotation occurs annually. A 6-month overlap period is maintained: the old key remains valid in
  Sparkle until 6 months after the new key is published, allowing operators running the application
  without auto-update access time to receive a signed update under the old key.
- After the 6-month overlap, the old key is destroyed. The destruction is documented in the release
  changelog.
- If the private key is believed compromised, an emergency rotation is performed immediately. The
  old key is revoked by publishing an appcast entry that delivers a mandatory update; the updated
  binary embeds only the new public key.

### Consequences

- **Positive** — no sandbox friction; no App Store review; Gatekeeper green on first launch;
  auto-update is straightforward; the embedded public key prevents post-notarization Info.plist
  substitution.
- **Negative** — requires an active Apple Developer Program enrolment ($99/year) and a Developer ID
  Application certificate; notarization adds one to fifteen minutes to release time; Sparkle
  introduces a third-party dependency with its own security surface; air-gapped signing requires a
  dedicated release workflow.
- **Neutral** — App Store distribution remains a future option once the sandbox-restricted feature
  set is acceptable.

### Confirmation

- A clean macOS 14 virtual machine launches the downloaded DMG, drags the `.app` into Applications,
  opens it, and Gatekeeper does not display a quarantine warning.
- `spctl --assess --verbose=4 /Applications/K8sManager.app` reports `accepted` and
  `source=Notarized Developer ID`.
- `codesign --verify --deep --strict /Applications/K8sManager.app` exits 0.
- `stapler validate /Applications/K8sManager.app` reports the staple is present and valid.
- `otool -l K8sManager.app/Contents/MacOS/K8sManager | grep cryptexec` returns output confirming the
  hardened runtime flag is set; the absence of this flag is a build-blocking CI failure.
- `pkgutil --check-signature K8sManager.app` reports the bundle is signed with a Developer ID
  Application certificate; the command exits 0 and the output includes
  `Status: signed by a developer certificate issued by Apple`.
- The appcast endpoint is reachable exclusively via HTTPS: a `curl` probe with `--proto '=https'`
  succeeds; the same probe without the flag but forcing `http://` URL scheme fails with a 301
  redirect that the application refuses to follow (verified by unit test asserting the URL scheme
  check returns an error for non-HTTPS appcast URLs).
- A unit test asserts that `UpdateChannelConfig.publicEdDSAKey` is a non-empty string that matches
  the expected Base64-encoded key value; the `Info.plist` key `SUPublicEDKey` is absent from the
  built bundle (verified by `plutil -p` output check in CI).
- The Homebrew Cask formula contains a `sha256:` field matching the published DMG; Homebrew formula
  lint (`brew audit --strict`) passes.

## Pros and cons of the options

### Option A — Developer ID + notarization

- **Pros** — full filesystem and subprocess access; no review queue; Gatekeeper trusted; integrates
  with Sparkle and Homebrew Cask.
- **Cons** — $99/year developer enrolment; manual or automated notarization step; signing-key
  management.

### Option B — Mac App Store

- **Pros** — discoverability; managed updates; user payment plumbing.
- **Cons** — sandbox prevents arbitrary kubeconfig access and exec plugins; review queue; in-app
  purchase rules; no Sparkle.

### Option C — Ad-hoc signed, no notarization

- **Pros** — zero infrastructure cost.
- **Cons** — Gatekeeper warning on first launch; users must `xattr -d com.apple.quarantine`; smell
  of an untrusted application.

### Option D — Homebrew tap with unsigned binary

- **Pros** — minimal infrastructure.
- **Cons** — Gatekeeper rejects unsigned binaries by default; users must manually allow execution;
  not acceptable for a polished product.

## More information

- ADR-0001 — macOS runtime choice (depends on this).
- ADR-0003 — Read-only kubeconfig (compatible with sandbox-free distribution).
- Future ADR — telemetry and crash reporting, which interact with Apple's privacy review even
  outside the App Store.
