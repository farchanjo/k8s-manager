# ADR-0054 — Welcome tab and cluster-acquisition entry surface

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0021 (app shell design system and main layout), ADR-0050 (resource navigation
  taxonomy)
- Tags — welcome-tab, onboarding, cluster-acquisition, app-shell, multi-document-tabs

## Context and problem statement

ADR-0050 defines a multi-document tab bar backed by `OpenTabsActor` with tab kinds for each
resource category (Workloads, Config, Network, etc.). The tab bar currently has no first-party
"home" position — when the operator has no clusters connected there is nothing to render in the
content area except the empty-state hint already specified in `onboarding.feature`.

The feature gap analysis in `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`
(reference items R2 and R8) identifies two related gaps:

- **R2** — The tab strip has no Welcome tab. Onboarding is modal (a transient overlay that
  dismisses after three steps). A persistent Welcome tab that operators can navigate back to
  at any time is absent.
- **R8** — The Welcome screen in the reference UI (Lens × Mirantis Prism AI) exposes five
  canonical start actions: Open Onboarding Wizard, Add Kubeconfig from clipboard, Add Kubeconfig
  from filesystem, Add Clusters from AWS, and Add Clusters from AKS. K8S-Manager has no
  equivalent surface.

The existing `onboarding.feature` modal is not a replacement for the Welcome tab:

- The modal is shown once at first launch and dismissed by the operator.
- After dismissal the modal does not reappear unless the operator resets onboarding state from
  Settings.
- The modal cannot host persistent cluster-acquisition actions (clipboard paste, file import,
  cloud discovery) because its purpose is to narrate the product, not to act as a launch pad
  throughout the session.

The Welcome tab must be a distinct `DocumentTab` kind that coexists with the modal flow rather
than replacing it.

## Decision drivers

- **Discoverability** — operators who want to add a second cluster after completing onboarding
  have no obvious entry point today. The cluster strip `+` button is the only path, and it does
  not surface cloud provider discovery.
- **Persistence** — the Welcome tab must be available on demand at any time, not just at
  first launch. It should not be closable or lost after the first workflow.
- **Separation of concerns** — the first-launch overlay (three-step tour) is an onboarding
  narration flow. Cluster acquisition (paste, import, cloud discovery) is an operational
  workflow. Conflating them in a single surface creates a modal that is too wide in scope.
- **Lean on ADR-0050** — the tab system is already defined. Extending it with a new
  `DocumentTab` kind (`welcome`) is the smallest-footprint approach and preserves all
  existing tab lifecycle rules (persistence, watch ownership, keyboard navigation).
- **Extensibility** — the Welcome tab's action catalogue must be extensible. Cloud provider
  discovery flows (AWS, AKS) are specified here with entry points only; the implementation
  contracts for each provider are deferred to ADR-0055. GCP discovery is deferred to
  ADR-0055 explicitly.

## Considered options

- **Option A** — Persistent Welcome `DocumentTab` with canonical action buttons (chosen).
- **Option B** — Expand the first-launch modal to include cluster-acquisition actions and
  make it reopenable from Settings.
- **Option C** — Add cluster-acquisition actions to the cluster strip `+` popover.

## Decision outcome

Chosen option — **Option A**, because:

- A dedicated tab kind is the most discoverable and persistent surface. Operators can navigate
  to it from the tab bar or the command palette at any time without recalling where the entry
  point is.
- Option B conflates narration (onboarding tour) with ongoing operational workflows. The modal
  is designed for a linear three-step sequence; adding non-linear actions to it produces a
  confusing UX.
- Option C puts too much responsibility on the `+` button, which today opens a kubeconfig
  cluster picker and does not have the visual weight to host five labelled action tiles.

---

## Welcome `DocumentTab` kind specification

### Tab identity

The Welcome tab is a `DocumentTab` with kind `welcome`. It does not carry a `resourceId`,
`namespace`, or `clusterId` — it is workspace-scoped, not cluster-scoped.

`DocumentTab` fields for the Welcome tab instance:

- `kind` — `welcome`
- `title` — `"Welcome"`
- `icon` — the system symbol `"hand.wave"` (SF Symbols)
- `isPinned` — `true` (always; see persistence rules below)
- `clusterId` — `nil`

### Persistence rules

- The Welcome tab is added to the workspace tab list on first launch, before the first-launch
  modal is presented.
- It is stored in the `OpenTabsActor` persistence payload (`tabs-state.json` per ADR-0026).
- It is restored on every cold launch regardless of whether onboarding is complete.
- If the persistence payload does not contain a `welcome` tab entry (e.g. migration from a
  prior build), a new Welcome tab instance is injected at position 0 on cold launch.

### Never auto-closed

The Welcome tab is exempt from all auto-close rules defined in ADR-0050:

- It is not closed when the operator closes all other tabs.
- It is not closed when the operator disconnects all clusters.
- It does not receive a close button in the tab bar. The `×` affordance is hidden for tabs
  with kind `welcome`.

### Reopen via command palette

If the operator has navigated away from the Welcome tab and it is not currently visible in the
tab bar scroll region, the command palette (ADR-0023) exposes a `Go to Welcome tab` command
(`⌘⇧W` — reserved; conflicts checked at implementation) that scrolls the tab bar to the
Welcome tab and activates it.

The command palette entry is always visible; it is not conditional on any cluster state.

### Single-instance per workspace

Only one `DocumentTab` of kind `welcome` is allowed in the workspace at any time. `OpenTabsActor`
enforces this invariant: if a `welcome` tab already exists, activating `Go to Welcome tab` or
the command palette entry navigates to the existing instance rather than creating a second one.

---

## Five canonical start actions

The Welcome tab content area presents five action tiles in a two-column grid layout. Each tile
carries a title, a brief description, and an SF Symbols icon.

### Action 1 — Open Onboarding Wizard

- Title: `"Open Onboarding Wizard"`
- Icon: `"list.bullet.clipboard"`
- Description: `"Restart the getting-started tour."`
- Behaviour: resets onboarding state to `notStarted` and presents the first-launch modal overlay
  at step 1. The Welcome tab remains in the tab bar behind the overlay.
- Availability: always visible.

### Action 2 — Add Kubeconfig from clipboard

- Title: `"Add Kubeconfig from Clipboard"`
- Icon: `"doc.on.clipboard"`
- Description: `"Paste a YAML kubeconfig directly — no file needed."`
- Behaviour: opens a sheet that reads the macOS pasteboard, parses the content as a YAML
  kubeconfig, and on success calls the existing `cluster_connectivity` import path.
  On parse failure a validation error is shown inline in the sheet.
- Implementation contract: deferred to ADR-0056.
- Availability: always visible.

### Action 3 — Add Kubeconfig from filesystem

- Title: `"Add Kubeconfig from File"`
- Icon: `"folder.badge.plus"`
- Description: `"Browse to a kubeconfig file on disk."`
- Behaviour: opens the macOS native file panel filtered to YAML and JSON files. On selection
  the file is parsed and imported via the `cluster_connectivity` import path (already specified
  in `cluster_connectivity/features/load-kubeconfig.feature`).
- Availability: always visible.

### Action 4 — Add Clusters from AWS

- Title: `"Add Clusters from AWS"`
- Icon: `"cloud.fill"` (provider icon overlay added at implementation)
- Description: `"Discover EKS clusters reachable with your current AWS credentials."`
- Behaviour: triggers the AWS EKS cluster discovery flow. Implementation contract deferred to
  ADR-0055.
- Availability: always visible. If AWS credentials are not configured, the flow presents an
  inline message guiding the operator to configure the credential adapter before discovery.

### Action 5 — Add Clusters from AKS

- Title: `"Add Clusters from AKS"`
- Icon: `"cloud.fill"` (provider icon overlay added at implementation)
- Description: `"Discover AKS clusters reachable with your current Azure credentials."`
- Behaviour: triggers the AKS cluster discovery flow. Implementation contract deferred to
  ADR-0055.
- Availability: always visible. Same unauthenticated-credential fallback as Action 4.

> Note: GCP discovery (GKE) is deferred to ADR-0055 and will be added as a sixth action
> tile when ADR-0055 is accepted. The Welcome tab layout must accommodate six tiles without
> redesign — the two-column grid expands naturally.

---

## Useful Guides links section

Below the five action tiles, the Welcome tab presents a "Useful Guides" section with three
static links rendered as tappable `Link` controls:

- `"Getting Started"` — links to the product documentation root.
- `"Using the AI Assistant"` — links to the assistant feature documentation.
- `"Getting Support"` — links to the support channel.

Link targets are configurable in the app bundle's `Info.plist` under the keys
`WelcomeGuideLinkGettingStarted`, `WelcomeGuideLinkAssistant`, `WelcomeGuideLinkSupport`.
This allows updating link targets without a source code change.

---

## Relationship to existing first-launch onboarding overlay

The first-launch modal overlay specified in `onboarding.feature` is preserved without change.
Its lifecycle is:

- Shown on first launch if onboarding state is `notStarted`.
- Skipped (dismissed) on `Escape`.
- Completable in three steps.
- Resumable from Settings → General → "Restart onboarding tour".

The Welcome tab and the onboarding overlay are complementary:

- The overlay narrates. The Welcome tab acts.
- The overlay is transient. The Welcome tab is persistent.
- The Welcome tab's "Open Onboarding Wizard" action is the re-entry point to the overlay for
  operators who want to run the tour again.

The two surfaces must not be confused in implementation. The Welcome tab does NOT replace
the `onboarding.feature` scenarios. Any scenario in `onboarding.feature` that references
an "empty state view" or "main window" continues to apply as written.

---

## Pros and cons of the options

### Positive

- Cluster acquisition has a dedicated, always-available surface. Operators adding a second
  or third cluster after onboarding no longer need to remember where the `+` button is.
- The Welcome tab decouples the narration flow (onboarding modal) from operational workflows
  (cluster acquisition actions), keeping each surface focused.
- Cloud provider discovery flows (AWS, AKS, GCP) have a designated entry point in the Welcome
  tab before their implementation contracts are finalised in ADR-0055.
- The tab-kind extension pattern validated here (`DocumentTab` kind `welcome`) establishes a
  template for future workspace-scoped tabs (e.g. a future "What's New" tab or a "Diagnostics"
  tab).

### Negative

- `OpenTabsActor` must enforce the single-instance invariant for kind `welcome`. This adds
  a guard branch to the tab-open path.
- The Welcome tab must be injected into the persistence payload on migration. A migration
  step is needed to avoid the Welcome tab being absent for operators who upgrade from a build
  that did not include it.
- Hiding the `×` close affordance for a specific tab kind requires a conditional in
  `TabBarView`. This is a small but visible deviation from a uniform tab component.

---

## Confirmation

- Gherkin feature `docs/arch/contexts/app_shell/features/welcome-tab.feature` covers the
  five canonical start actions, the never-auto-closed lifecycle, reopen via command palette,
  and single-instance enforcement.
- `OpenTabsActor` unit tests assert the `welcome` kind single-instance invariant and the
  position-0 injection on migration.
- A snapshot test captures the Welcome tab layout (two-column action grid plus Useful Guides
  links) in light and dark mode.
- The shortcut `⌘⇧W` is verified against the ADR-0023 shortcut registry before implementation.

## Followups

- ADR-0055 — Cloud provider cluster discovery (AWS, Azure, GCP) — specifies provider port
  contracts, credential validation flows, and kubeconfig materialisation.
- ADR-0056 — Kubeconfig import from clipboard — specifies the paste-and-validate sheet and
  the integration with the existing `cluster_connectivity` import path.
- The two-column action grid layout must be verified at reduced-motion settings.

## More information

- ADR-0021 — App shell design system; original `NavigationSplitView` three-column layout.
- ADR-0023 — Command palette and shortcuts; governs the `Go to Welcome tab` command entry.
- ADR-0050 — Resource navigation taxonomy; defines `DocumentTab`, `OpenTabsActor`, tab
  persistence and auto-close rules. This ADR extends those rules with a `welcome` kind
  exemption.
- ADR-0051 — Multi-cluster workspace; defines the cluster strip `+` button that will
  continue to exist alongside the Welcome tab as a secondary cluster-add entry point.
- Feature gap analysis —
  `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`, section 5.1 (R2),
  section 5.2 (R8).
- `onboarding.feature` —
  `docs/arch/contexts/app_shell/features/onboarding.feature`
