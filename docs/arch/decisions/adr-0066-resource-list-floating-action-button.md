# ADR-0066 — Floating action button for resource creation

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0030 (integrated editor), ADR-0050 (resource navigation taxonomy),
  ADR-0061 (row action menu uniform shape)
- Tags — fab, floating-action-button, resource-creation, resource-browser, app-shell

## Context and problem statement

The reference recording (R28, `feature-gap-analysis-lens-prism-ai.md`) shows Lens surfacing a blue
`+` floating action button at the bottom-right corner of every resource list pane. Tapping the FAB
opens a create-resource flow scoped to the list's current kind and namespace. K8S-Manager has no
equivalent entry point: resource creation today flows exclusively through the YAML apply path
(`Edit YAML` on a selected resource) or an external `kubectl apply`. Neither path is discoverable
from a list view, and neither is kind-aware.

Three gaps follow:

1. **Entry-point discoverability** — there is no affordance visible in the list pane that signals
   "you can create a resource here".
2. **Kind-aware skeleton templates** — operators who want to create a new Deployment or ConfigMap
   must supply the full manifest from memory. A skeleton template pre-filled with the kind's
   required fields reduces error and authoring time.
3. **Clipboard-driven and fork-driven creation** — operators frequently have a manifest on the
   clipboard (from documentation, another tool, or AI output) or want to clone an existing row with
   a new name. Neither workflow is explicitly supported today.

## Decision drivers

- Entry-point discoverability for creation: a persistent, visually salient button in the list pane
  makes the create action zero-navigation.
- Kind-aware templates speed up authoring: pre-filling required fields from a skeleton reduces
  invalid-manifest submissions and first-submission dry-run failures.
- Clipboard and fork paths reduce friction for the two most common non-scratch creation workflows.
- FAB must respect the ADR-0013 operation matrix: kinds that do not carry a `create` operation MUST
  NOT show a FAB.
- Keyboard accessibility: the FAB must have a keyboard shortcut and a VoiceOver label.
- Integration with ADR-0030 (integrated editor) and ADR-0064 (inline docked YAML editor pane): the
  create flow reuses the existing editor infrastructure; it does not introduce a separate text-entry
  surface.

## Considered options

- **Option A** — No FAB; rely on the command palette (ADR-0023) and the toolbar for creation.
- **Option B** — FAB opens a generic apply-YAML sheet (plain text area, no kind context).
- **Option C** — FAB opens a kind-aware create flow with three paths: apply from scratch with a
  kind skeleton, paste from clipboard, fork from the selected row.

## Decision outcome

Chosen option — **Option C**, because:

- Option A requires operators to know the command palette shortcut; it is not discoverable in the
  list pane and does not reduce template authoring effort.
- Option B improves discoverability but not template ergonomics: operators still author the entire
  manifest from memory.
- Option C combines discoverability (persistent FAB), template ergonomics (kind skeleton), and the
  two most common non-scratch creation workflows (clipboard, fork). The three-path popover is a
  single additional interaction level above Option B and is familiar from mobile and IDE creation
  dialogs.

### FAB chrome

- Shape: 56 pt diameter circle.
- Background: `accentBrand` fill.
- Glyph: white `+` (SF Symbol `plus`, weight `.semibold`).
- Position: 16 pt from the bottom edge and 16 pt from the trailing edge of the list pane frame.
  The FAB is inset from the pane border, not the window chrome.
- Drop shadow: `shadowElevation2` design token (4 pt blur radius, 2 pt y-offset, 20% black).
- The FAB floats above the list scroll content; it does not participate in the scroll layout.

### FAB visibility rules

The FAB is visible on resource list panes for kinds whose `ResourceKindDescriptor.permittedOperations`
includes `create` in the ADR-0013 operation matrix. The FAB is hidden (not merely disabled) for
kinds that do not carry `create`, including:

- `Node` (cluster-scoped, read-mostly; no `create` in ADR-0013 matrix).
- `Event` (events feed; append-only from the cluster, not operator-created).
- `CSINode`, `CSIDriver` (infrastructure-managed; no `create`).
- Any kind whose `ResourceKindDescriptor.permittedOperations` does not include `create`.

The visibility decision is derived exclusively from the operation matrix; it is not hardcoded per
kind name. New kinds added to the catalogue that include `create` automatically receive a FAB
without additional UI code.

### Click action — three-path popover

Clicking the FAB (or pressing `⌘N` while a list pane is focused) presents a popover anchored to
the FAB with three items:

1. **Create from scratch** — opens the ADR-0064 inline docked YAML editor with the kind skeleton
   template for the current kind pre-filled (see "Kind skeleton templates" below). The editor opens
   in edit mode (`#StateEditing`); the operator can author the manifest and apply via the standard
   ADR-0030 apply pipeline.

2. **Paste from clipboard** — reads the system clipboard. If the clipboard content parses as valid
   YAML or JSON, opens the ADR-0064 inline docked YAML editor with that content pre-filled. If the
   clipboard content is not parseable as YAML or JSON, shows an inline error toast:
   "Clipboard content is not valid YAML or JSON" and does not open the editor. The parsed content
   is not validated against the kind schema at paste time; validation runs via the ADR-0030
   real-time validation pipeline once the editor opens.

3. **Fork from selected** — enabled only when exactly one row is selected in the list. Performs a
   deep copy of the selected resource's spec, then resets the following metadata fields to their
   create-safe defaults:

   - `metadata.name` — set to `<original-name>-copy` (operator edits before apply).
   - `metadata.namespace` — retained from the original.
   - `metadata.resourceVersion` — removed.
   - `metadata.uid` — removed.
   - `metadata.creationTimestamp` — removed.
   - `metadata.generation` — removed.
   - `metadata.managedFields` — removed.
   - `status` — removed (status is server-set).

   The resulting manifest opens in the ADR-0064 inline docked YAML editor in edit mode.

   When no row is selected the "Fork from selected" item is present but disabled (greyed, not
   hidden), with a tooltip: "Select a row first".

### Kind skeleton templates

Each kind for which `create` is a permitted operation has a corresponding YAML skeleton template.
Templates are stored under `docs/arch/contexts/resource_browser/schemas/templates/` (one file per
kind, named `<kind-lowercase>-skeleton.yaml`, e.g., `deployment-skeleton.yaml`). Template files
are bundled into the application at build time; no network fetch is required.

A skeleton template is a minimal valid manifest for the kind: it includes all required fields,
uses placeholder values wrapped in angle brackets (e.g., `<name>`, `<namespace>`, `<image>`), and
omits optional fields. The editor's real-time validation pipeline (ADR-0030) immediately marks
placeholder values as schema warnings, guiding the operator to fill them in before applying.

The initial set of kind skeleton templates (to be authored in a follow-up task):

- `Deployment`, `StatefulSet`, `DaemonSet`, `ReplicaSet`, `Job`, `CronJob`
- `Pod`, `HorizontalPodAutoscaler`
- `ConfigMap`, `Secret`, `ServiceAccount`
- `PersistentVolumeClaim`, `ResourceQuota`, `LimitRange`
- `Service`, `Ingress`, `NetworkPolicy`
- `Role`, `RoleBinding`, `ClusterRole`, `ClusterRoleBinding`
- `Namespace`

CRD instances do not have a static skeleton; the "Create from scratch" path for a CRD kind opens
an empty YAML editor pre-filled with the minimum envelope (`apiVersion`, `kind`, `metadata.name`,
`metadata.namespace`) derived from the CRD's `spec.versions[0].schema.openAPIV3Schema`.

### Keyboard shortcut

`⌘N` while focus is inside a resource list pane opens the same three-path popover as clicking the
FAB. If a list pane is not focused, `⌘N` has no effect from the FAB context; the command palette
remains the fallback for creation outside a list pane.

### Accessibility

- The FAB has `accessibilityLabel` set to "Create \<Kind\>" (e.g., "Create Deployment"), using the
  kind name of the active list pane.
- The FAB has `accessibilityHint` set to "Opens a menu with options to create a new resource from
  scratch, from clipboard, or by forking a selected row."
- The focus ring on keyboard navigation is the standard macOS focus ring at 3 pt offset from the
  button perimeter.
- Each popover item is individually focusable via VoiceOver and announces its label and enabled
  state.
- The "Fork from selected" item announces "dimmed" when disabled.

## Followups

- Author the skeleton template YAML files under
  `docs/arch/contexts/resource_browser/schemas/templates/` for each kind listed above.
- Verify `⌘N` does not conflict with any shortcut in the ADR-0023 registry; reserve the binding.
- Confirm `create` operation availability per kind against the ADR-0013 + ADR-0050 operation
  matrix and update the `ResourceKindDescriptor` CUE schema to include `create` as a permitted
  operation value.
- Define the payload size threshold for async deep-copy in the "Fork from selected" path.
- ADR-0064 (inline docked YAML editor pane) must be ratified before the FAB create paths can be
  implemented; this ADR is a consumer of ADR-0064.

## Pros and cons of the options

### Option A — No FAB; rely on command palette and toolbar

- Good, because no new UI component is introduced.
- Bad, because creation is not discoverable from the list pane; operators must know the command
  palette shortcut.
- Bad, because the command palette is not kind-context-aware; it cannot pre-fill a skeleton or
  fork a selected row.

### Option B — FAB opens a generic apply-YAML sheet

- Good, because a single sheet implementation covers all kinds.
- Good, because a FAB improves discoverability over Option A.
- Bad, because the generic sheet provides no template scaffolding; operators author the full
  manifest from memory, which was identified as a friction point in the feature gap analysis.
- Bad, because clipboard and fork paths are not first-class; they require additional manual steps.

### Option C — FAB opens a kind-aware create flow with three paths (chosen)

- Good, because kind skeleton templates reduce authoring friction.
- Good, because clipboard and fork paths are first-class menu items.
- Good, because FAB visibility is derived from the operation matrix, requiring no per-kind
  hardcoding.
- Bad, because skeleton templates require a content authoring phase for each kind.
- Bad, because the "Fork from selected" path has a payload size consideration for large resources.

## Confirmation

- `contexts/resource_browser/schemas/resource_kind_descriptor.cue` is updated to add `create` as
  a valid member of the `permittedOperations` enum, and the affected kind descriptors are updated
  accordingly. CI `cue:vet` validates the schema.
- Rego policy `contexts/resource_browser/policies/resource_mutation_policy.rego` enforces that a
  create operation is only allowed for kinds whose descriptor includes `create`.
- Gherkin features under `contexts/resource_browser/features/list-floating-action-button.feature`
  cover: FAB visible on workloads list, FAB hidden on Nodes list, create-from-scratch opens kind
  skeleton, paste-from-clipboard parses and pre-fills, fork-from-selected deep-copies and resets
  metadata.
- Unit test: `FabVisibilityPolicy` returns `hidden` for `Node` and `visible` for `Deployment`.
- Unit test: the fork path removes `metadata.uid`, `metadata.resourceVersion`,
  `metadata.managedFields`, and `status` from the deep-copied manifest.
- Unit test: the clipboard path returns an error result when the clipboard contains non-YAML/JSON
  content.

## More information

- ADR-0013 — Resource browser scope; per-kind operation matrix (source of `create` eligibility).
- ADR-0023 — UX patterns; command palette and shortcut registry (verify `⌘N` availability).
- ADR-0030 — Integrated editor; the create flow opens the ADR-0030 editor in a mode compatible
  with ADR-0064.
- ADR-0050 — Resource navigation taxonomy; kind catalogue and sidebar tree.
- ADR-0061 — Row action menu uniform shape; the FAB popover follows the same visual language.
- ADR-0064 — Inline docked YAML editor pane (forward reference; must be ratified before
  implementation).
- `feature-gap-analysis-lens-prism-ai.md` R28 — reference recording observation that motivated
  this ADR.
- `contexts/resource_browser/schemas/templates/` — skeleton template YAML files (to be authored
  in followup).
