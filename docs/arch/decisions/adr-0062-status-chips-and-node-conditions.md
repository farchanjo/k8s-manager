# ADR-0062 — Status chips and node conditions presentation

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0021 (app shell design system and main layout), ADR-0050 (resource navigation
  taxonomy)
- Tags — status-chips, badges, node-conditions, resource-browser, design-system

## Context and problem statement

The reference recording (R26 — Lens × Mirantis Prism AI, `Screen Recording 2026-05-16 at
13.19.58.mov`) shows a green "Ready" pill on every node row in the Nodes list view. This visual
affordance lets operators scan fleet health at a glance without opening the detail drawer for each
node.

K8S-Manager currently surfaces workload status through an existing `StatusBadge` SwiftUI view
(located at `AppShell/Views/Resources/Workloads/StatusBadge.swift`). No equivalent component exists
for node conditions. The workload `StatusBadge` is implemented in an ad-hoc, per-kind fashion and
its visual language (colour, shape, icon policy, tooltip contract) has never been formally
specified. As more kinds acquire status indicators — nodes, persistent volumes, custom resources —
the absence of a shared semantic mapping will produce visual incoherence and make accessibility
compliance impossible to audit uniformly.

This ADR standardises the chip component and its kind-specific semantic mappings for all resource
kinds that carry machine-readable conditions or phase fields in the Kubernetes API.

## Decision drivers

- **Operator scanning speed** — an operator managing a fleet of dozens of nodes must identify
  unhealthy nodes within a single visual pass of the list. Colour alone is insufficient; icon and
  label must reinforce the signal (WCAG 1.4.1).
- **Colour-blind accessibility** — the design system (ADR-0021) prohibits colour-only
  communication. Every chip variant must carry a leading SF Symbol icon so that the state is
  distinguishable without colour perception.
- **Hover-explainability** — the raw Kubernetes condition message (e.g.,
  `"kubelet has sufficient memory available"`) must be surfaced on hover so operators can triage
  without opening the detail drawer.
- **Consistency across kinds** — a single reusable `StatusChip` SwiftUI view replaces per-kind
  ad-hoc badge implementations, reducing duplication and unifying the visual language.
- **Composability** — the chip must compose cleanly into both list-row cells (compact, single
  chip or stacked chips) and the detail drawer resource header (full-width, multi-condition
  layout).

## Considered options

- **Option A — Per-kind ad-hoc chip.** Each kind's list view owns its own badge implementation.
  Colours, labels, and icon choices are decided at the list-view level with no shared contract.

- **Option B — Unified `StatusChip` with kind-specific semantic mapping (chosen).** A single
  SwiftUI view parameterised by `StatusChipVariant` and `label`/`tooltip` strings. Kind-specific
  mapping functions translate Kubernetes API condition types and phase values to chip parameters.
  The view is unaware of Kubernetes semantics; it only renders a variant + label + tooltip.

- **Option C — Colour-coded row backgrounds.** Instead of inline chips, the row background is
  tinted according to the worst condition. No chip component is needed; colour carries the full
  signal. No additional screen real estate is consumed.

## Decision outcome

Chosen option — **Option B**, because:

- It produces a single testable view for contrast-ratio audits and snapshot tests.
- Kind-specific mapping is decoupled from the view, allowing mapping rules to evolve without
  touching the component.
- Option A produces divergent chip implementations per kind that cannot be audited together.
- Option C uses colour as the sole state carrier, violating WCAG 1.4.1 and ADR-0021's
  "colour supplemented with shape or text" rule. Row backgrounds also interfere with selection
  and hover highlight states on macOS.

### StatusChip SwiftUI view contract

`StatusChip` is a value-type SwiftUI `View` declared in the `AppShell` SwiftPM target. It accepts
the following parameters:

- `variant` — one of the five semantic variants defined in `StatusChipVariant`: `success`,
  `warning`, `error`, `info`, `neutral`.
- `label` — a localised string displayed inside the chip (e.g., `"Ready"`, `"NotReady"`,
  `"Pending"`).
- `tooltip` — an optional string shown in a `help` tooltip on hover. When non-nil, it renders
  the raw `condition.message` value from the Kubernetes API response. When nil, no tooltip is
  attached.

`StatusChipVariant` maps to the design token and icon pair shown below. Colour tokens are defined
in `design_tokens.cue` (ADR-0021); icon names are SF Symbols 6.

- `success` — foreground `statusHealthy`, icon `checkmark.circle.fill`
- `warning` — foreground `statusWarning`, icon `exclamationmark.triangle.fill`
- `error` — foreground `statusError`, icon `xmark.circle.fill`
- `info` — foreground `accentBrand`, icon `info.circle.fill`
- `neutral` — foreground `statusUnknown`, icon `circle.fill`

The icon is always rendered as the leading element of the chip, before the label text. This
satisfies the WCAG 1.4.1 requirement: state is conveyed by both icon and colour, not by colour
alone.

The chip background is the variant foreground colour at 12% opacity, applied with a
`RoundedRectangle` with `RadiusTokens.small` (4 pt) corner radius. The chip height is fixed at
the row typography cap-height. Label text uses the `caption` text style at `medium` weight.

### Node conditions semantic mapping

The Kubernetes node conditions API (`node.status.conditions`) produces a list of typed conditions
each carrying `type`, `status` (`True`, `False`, `Unknown`), `reason`, and `message`. The mapping
below resolves each condition type to a `StatusChipVariant`.

`Ready` condition:

- `status == "True"` → `success`, label `"Ready"`
- `status == "False"` → `error`, label `"NotReady"`
- `status == "Unknown"` → `warning`, label `"Unknown"`

`SchedulingDisabled` (node carries the `node.kubernetes.io/unschedulable` taint):

- Taint present → `warning`, label `"SchedulingDisabled"`

Pressure conditions (`MemoryPressure`, `DiskPressure`, `PIDPressure`):

- `status == "True"` → `error`, label matching the condition type (e.g., `"MemoryPressure"`)
- `status == "False"` → condition is healthy; chip is suppressed (not shown in the list row)
- `status == "Unknown"` → `warning`, label matching the condition type

`NetworkUnavailable` condition:

- `status == "True"` → `error`, label `"NetworkUnavailable"`
- `status == "False"` → chip suppressed
- `status == "Unknown"` → `warning`, label `"NetworkUnavailable"`

Chip rendering in the list row shows the single worst-severity chip when multiple conditions are
active simultaneously. Severity order from highest to lowest: `error` > `warning` > `success` >
`info` > `neutral`. When only `Ready=True` and no pressure conditions are active, the row shows
the single `success` chip for `Ready`. When a pressure condition coexists with `Ready=True`, the
pressure `error` chip replaces the `Ready` chip in the row; the full condition set is visible in
the detail drawer.

The detail drawer resource header renders all active (non-suppressed) chips as a horizontal
`FlowLayout` row, without the single-worst-severity compaction applied to list rows.

### Pod phase mapping

The Kubernetes pod phase (`pod.status.phase`) maps as follows:

- `Running` and all containers have `ready == true` → `success`, label `"Running"`
- `Running` and one or more containers have `ready == false` → `warning`, label `"Degraded"`
- `Pending` → `warning`, label `"Pending"`
- `Failed` → `error`, label `"Failed"`
- `Succeeded` → `neutral`, label `"Succeeded"`
- `Unknown` → `warning`, label `"Unknown"`

The `CrashLoopBackOff` waiting reason in any container's `state.waiting.reason` overrides the pod
phase chip to `error`, label `"CrashLoopBackOff"`, regardless of phase value. This override is
checked before the phase mapping.

### Deployment, StatefulSet, and DaemonSet status mapping

The readiness ratio chip is derived from the kind-specific status fields:

- Deployment: `status.readyReplicas` / `status.replicas`
- StatefulSet: `status.readyReplicas` / `status.replicas`
- DaemonSet: `status.numberReady` / `status.desiredNumberScheduled`

The chip label is `"<ready>/<desired>"` (e.g., `"3/3"`, `"2/3"`).

Variant rules:

- `ready == desired` and `desired > 0` → `success`
- `ready < desired` and the condition has persisted for less than 5 minutes → `warning`
- `ready < desired` and the condition has persisted for 5 minutes or more → `error`
- `desired == 0` → `neutral`, label `"0/0"`

The 5-minute threshold is evaluated against the timestamp of the last observed transition in the
resource's condition list. When a precise transition timestamp is not available from the API, the
warning-to-error promotion is deferred until the next watch event carries a confirmed timestamp.

### Hover tooltip contract

The `tooltip` parameter of `StatusChip` is populated from the `condition.message` field of the
Kubernetes API object for the condition that produced the chip. For pod phase chips, the tooltip is
populated from `pod.status.message` when present, or from the container's
`state.waiting.message` for the first non-ready container when the phase chip is derived from
container state.

The tooltip is attached to the chip using SwiftUI's `.help(_:)` modifier. It is visible on hover
and is accessible via VoiceOver as a supplementary accessibility label appended to the chip's
primary accessibility label (e.g., `"Ready. kubelet has sufficient memory available"`).

### Colour-blind accessibility

Each `StatusChipVariant` leads with an SF Symbol icon chosen to be distinguishable by shape alone,
without relying on colour perception. The icon set is:

- `success` — `checkmark.circle.fill` (circular check; universally recognised as affirmative)
- `warning` — `exclamationmark.triangle.fill` (triangular; distinct from circular shapes)
- `error` — `xmark.circle.fill` (circular X; distinct from checkmark by mark shape)
- `info` — `info.circle.fill` (circular i; reserved for informational, non-alarm states)
- `neutral` — `circle.fill` (unfilled dot; minimal signal, used for terminal/inactive states)

All five icons are rendered in `.palette` rendering mode with the variant foreground colour on
the primary layer and `surfaceBackground` on the secondary layer, consistent with ADR-0021's
status indicator rendering policy.

The chip label text must always be present. A chip without a label is a contract violation and
must not be used.

### Accessibility label policy

Each `StatusChip` instance exposes a single concatenated `.accessibilityLabel` of the form
`"<label> status"` (e.g., `"Ready status"`, `"NotReady status"`). When a tooltip is set, it is
appended as a separate `.accessibilityHint` (e.g., `"kubelet has sufficient memory available"`).
This matches the pattern established in ADR-0021 for status bar indicators.

## Pros and cons of the options

Positive:

- A single `StatusChip` component covers all resource kinds; snapshot tests and contrast-ratio
  checks need to target one component rather than N per-kind badge implementations.
- Node rows gain health visibility at a glance (closes gap R26 from the feature-gap analysis).
- The tooltip contract makes condition messages accessible without opening the detail drawer,
  reducing navigation overhead for fleet operators.
- WCAG 1.4.1 compliance is enforced structurally: the icon-leading policy is part of the
  component contract, not a per-use-site decision.

Negative:

- The 5-minute warning-to-error promotion for Deployment/StatefulSet/DaemonSet requires
  timestamp tracking in the view model layer. View models for these kinds must record the first
  observed `ready < desired` timestamp and re-evaluate the variant on the next watch event.
- The single-worst-severity compaction in list rows discards information. Operators who want to
  see all active conditions on a node must open the detail drawer. This is an acceptable
  trade-off for list density but must be clearly communicated in onboarding documentation.
- Migrating the existing `StatusBadge` workload implementation to `StatusChip` is a breaking
  visual change for workload list views. The migration should be done in a single coordinated
  pass across all workload list views to avoid a mixed-component state.

## Followups

- Migrate `StatusBadge` (workload list views) to `StatusChip` in a single pass; deprecate and
  remove `StatusBadge` after migration.
- Add `StatusChip` to the `design_tokens.cue` snapshot test suite to verify that all five
  variant colour/icon pairs pass the 3:1 contrast ratio check against `surfaceBackground` in
  both light and dark appearances (ADR-0021 requirement).
- Add `StatusChipVariant` CUE definition to
  `contexts/resource_browser/schemas/status_chip_variant.cue`.
- Extend `ResourceDetailDrawer` to render the full multi-condition `FlowLayout` row for nodes
  in the resource header section.
- Record the `NodeConditionsSummary` read model in
  `contexts/resource_browser/schemas/node_conditions_summary.cue` carrying: `nodeId`,
  `worstVariant`, `conditions` (array of `{type, variant, label, message}`).

## Confirmation

- `StatusChip` snapshot tests cover all five variants in light and dark appearances; pixel
  comparison must not drift.
- A contrast-ratio test asserts that the label foreground of each variant meets 4.5:1 against
  its tinted background in both appearances.
- An accessibility audit confirms that VoiceOver reads `"<label> status"` followed by the
  tooltip hint for a chip with a non-nil tooltip.
- Gherkin features `node-conditions-chip.feature` under
  `contexts/resource_browser/features/` cover the five key scenarios (ready, not-ready,
  scheduling-disabled, memory-pressure override, tooltip content).
- An integration test renders `NodesListView` with a mock node list containing one
  `Ready=True` node, one `Ready=False` node, one `MemoryPressure=True, Ready=True` node, and
  one `Unschedulable=true` tainted node, and asserts the four distinct chip variant values.

## More information

- ADR-0021 — Design system; status semantic tokens (`statusHealthy`, `statusWarning`,
  `statusError`, `statusUnknown`), WCAG accessibility requirements, SF Symbol rendering modes.
- ADR-0050 — Resource navigation taxonomy; defines the kinds that appear in the Nodes, Workloads,
  and other list views that this ADR extends with chips.
- ADR-0051 — Multi-cluster workspace; detail drawer resource header where multi-condition chips
  are rendered in full.
- Feature gap analysis, R26 — reference recording observation that prompted this ADR.
- `contexts/resource_browser/features/node-conditions-chip.feature` — Gherkin scenarios for
  this ADR.
