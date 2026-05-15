# ADR-0001 — macOS-native distribution via Swift and SwiftUI

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — distribution, platform, ui

## Context and problem statement

K8sManager targets desktop operators who manage Kubernetes clusters from
macOS workstations. Competing tools (Lens, OpenLens, Headlamp) ship as
cross-platform Electron applications. Electron carries a Chromium runtime,
elevated memory footprint, slower cold start, and visible non-native UI
behaviour on macOS (window chrome, keyboard handling, menu bar, drag and
drop, dark mode transitions).

We need to decide the application runtime, UI toolkit, and platform
coverage **before any code is written**, because the choice constrains
every subsequent decision (Kubernetes client, IPC, packaging, code
signing, sandboxing, telemetry).

## Decision drivers

- **Native feel** — macOS-idiomatic behaviour is a product differentiator.
- **Memory and startup footprint** — desktop operators expect sub-second
  cold start and low idle memory; Electron typically violates both.
- **Toolchain familiarity** — solo maintainer is comfortable with
  Apple-platform tooling.
- **Long-term maintenance cost** — the smaller the runtime surface, the
  fewer transitive dependencies to track.
- **MVP scope is small** — multi-cluster + context switch; no web UI
  parity needed.

## Considered options

- **Option A** — Swift + SwiftUI, macOS-only, target macOS 14 and later.
- **Option B** — Electron + TypeScript, cross-platform.
- **Option C** — Tauri + Rust + web front-end, cross-platform.
- **Option D** — Go + Fyne/Wails, cross-platform.

## Decision outcome

Chosen option — **Option A (Swift + SwiftUI, macOS 14+)**, because it is
the only option that delivers native macOS behaviour with no runtime
shim, has first-class access to Apple frameworks needed for keychain,
notarization, and code signing, and matches the maintainer's existing
toolchain.

### Consequences

- **Positive** — native window chrome, menu bar, keyboard shortcuts,
  drag and drop, dark mode, Accessibility, Spotlight integration come
  for free. Smallest possible binary. App size compatible with
  Developer ID distribution. SwiftUI Observation framework (macOS 14+)
  eliminates Combine/`@Published` boilerplate.
- **Negative** — Kubernetes ecosystem libraries are concentrated in Go
  and TypeScript; Swift coverage is community-driven (see ADR-0002).
  Linux and Windows users cannot run the application; documented as
  out-of-scope for the MVP.
- **Neutral** — macOS 14+ minimum cuts a small slice of users on macOS
  13 and earlier; revisit before 1.0 if telemetry justifies it.

### Confirmation

- Build produces a `.app` bundle that launches on a clean macOS 14
  virtual machine in under two seconds and idles below 50 MB resident.
- No `@available(macOS 15.x)` annotations are present in the
  domain or adapter layers.

## Pros and cons of the options

### Option A — Swift + SwiftUI

- **Pros** — native UI, minimal runtime, smallest binary, first-class
  Keychain and code-signing toolchain, modern concurrency
  (`async`/`await`).
- **Cons** — no cross-platform path; Kubernetes client ecosystem is
  thinner (mitigated in ADR-0002).

### Option B — Electron + TypeScript

- **Pros** — large Kubernetes client ecosystem (`@kubernetes/client-node`),
  cross-platform from day one, abundant UI components.
- **Cons** — non-native macOS feel, large binary (~150 MB), high idle
  memory, Chromium update cadence, frequent security advisories.

### Option C — Tauri + Rust

- **Pros** — small binary, memory-safe runtime, good Rust Kubernetes
  client (`kube-rs`), cross-platform.
- **Cons** — UI is still web-based; native macOS feel limited; mixed
  Swift/Rust toolchain not justified by MVP scope.

### Option D — Go + Fyne/Wails

- **Pros** — same language as Kubernetes itself, `client-go` is the
  reference client.
- **Cons** — Fyne UI is not macOS-native; Wails is web-based; neither
  is a fit for the desired feel.

## More information

- ADR-0002 — Kubernetes client choice (depends on this decision).
- ADR-0004 — Distribution and notarization (depends on this decision).
