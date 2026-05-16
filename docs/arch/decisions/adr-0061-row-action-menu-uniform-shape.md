# ADR-0061 — Per-row resource action menu uniform shape

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0012 (mutating operations policy), ADR-0050 (resource navigation taxonomy),
  ADR-0060 (resource list export CSV and YAML)
- Tags — action-menu, row-actions, resource-browser, uniform-ux

## Context and problem statement

Each list view in `resource_browser` currently defines its own row context-menu items in an ad-hoc
manner. Deployments expose Rollout Restart; some kinds expose Delete; others omit View Events
entirely. Operators who work across multiple resource kinds cannot build reliable muscle memory
because the action set, item ordering, and keyboard accelerators differ per view.

The gap analysis in `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md` (R25)
identified this as PARTIAL: some lists expose context menus but the shape — edit YAML / delete /
view events / copy resource link — is not uniform across all 51 kinds.

The detail drawer toolbar (ADR-0051) already specifies a subset of these actions for the
slide-in panel; the per-row 3-dot action menu is a distinct surface that must remain actionable
without opening the drawer.

## Decision drivers

- **Predictability** — operators must be able to invoke the same action on any kind without
  inspecting whether that action is present. Hidden or absent menu items cause discovery failures.
- **Keyboard coherence** — a fixed letter-key accelerator scheme must work consistently across all
  list views so that power operators can drive the application without lifting their hands from the
  keyboard.
- **Alignment with ADR-0012** — every mutating item in the menu is already governed by the
  mutation guard (mutation scope, single/double-confirm requirements, audit). The menu is a
  dispatch surface; it does not add new mutation semantics.
- **Accessibility** — VoiceOver must be able to describe every menu item with a consistent label
  and role regardless of the kind shown in the list.
- **Detail drawer toolbar parity** — the actions available in the per-row menu must be a subset of
  the actions available in the detail drawer toolbar (ADR-0051), so that selecting a row and
  opening the drawer never reveals unexpected actions that the row menu omitted.

## Considered options

- **Option A** — Per-kind freeform menus: each list view declares its own item set with no shared
  contract. Minimal shared code; maximum per-kind control; impossible to achieve keyboard
  coherence or operator muscle memory.
- **Option B** — Per-family canonical menu: a fixed item set per kind family (Workloads, Config,
  Network, Storage, Access Control, Custom Resources), with items that are inapplicable to a
  specific kind within the family rendered as disabled or hidden (see Decision outcome below).
- **Option C** — Globally identical menu for all kinds with disabled items per kind: a single
  13-item menu shown identically everywhere; items that do not apply to the current kind are
  disabled (greyed out) rather than hidden. Maximally discoverable; cluttered for sparse families
  such as Config.

## Decision outcome

Chosen option — **Option B**, per-family canonical menu, because:

- It satisfies predictability within a family without forcing operators to scan a list of
  inapplicable disabled items (as Option C would for sparse families).
- Keyboard accelerators can be uniform across all families because the base set (Edit YAML,
  Delete, Save YAML, Copy Resource Link, View Events) is identical; family-specific additions
  are clearly additive.
- Option A cannot achieve the muscle-memory requirement because there is no shared contract.
- Option C introduces visual clutter in Config and Storage families where most workload-specific
  items (Scale, Rollout Restart, View Logs, Open Terminal) do not apply.

Items that are inapplicable for a specific kind within a family are **hidden** (not disabled),
keeping the menu compact. The one exception is Delete: Delete is always present and always
enabled for any kind where the operator holds the required RBAC permissions.

### Kind families and canonical menu items

The following lists define the canonical item order for each kind family. Items listed under
"Base set (all families)" appear identically in every family and are listed first. Family-specific
items follow the base set.

#### Base set — present in every family

- Edit YAML (keyboard accelerator: E)
- View Events (keyboard accelerator: V)
- Copy Resource Link (keyboard accelerator: Cmd-C)
- Save YAML (keyboard accelerator: Y)
- Delete (keyboard accelerator: X; requires double-confirm per ADR-0012)

#### Workloads family

Kinds: Deployment, StatefulSet, DaemonSet, ReplicaSet, Pod, Job, CronJob,
HorizontalPodAutoscaler, ReplicationController.

Additional items appended after the base set:

- Scale (keyboard accelerator: S) — shown for Deployment, StatefulSet, ReplicaSet only
- Rollout Restart (keyboard accelerator: R) — shown for Deployment, StatefulSet, DaemonSet only
- View Logs (keyboard accelerator: L) — shown for Pod only
- Open Terminal (keyboard accelerator: T) — shown for Pod only

#### Config family

Kinds: ConfigMap, Secret, ServiceAccount, ResourceQuota, LimitRange, PodDisruptionBudget,
PriorityClass, RuntimeClass, Lease, MutatingWebhookConfiguration,
ValidatingWebhookConfiguration.

No additional items beyond the base set.

#### Network family

Kinds: Service, Ingress, NetworkPolicy, EndpointSlice, Endpoints, IngressClass.

Additional items appended after the base set:

- Port Forward (keyboard accelerator: F) — shown for Service and Pod (Pod appears under
  Workloads; the Port Forward item is also canonical for Service in the Network family)

#### Storage family

Kinds: PersistentVolume, PersistentVolumeClaim, StorageClass, VolumeAttachment.

No additional items beyond the base set.

#### Access Control family

Kinds: Role, ClusterRole, RoleBinding, ClusterRoleBinding.

Additional items appended after the base set:

- View Subjects (keyboard accelerator: U) — shown for RoleBinding and ClusterRoleBinding only

#### Custom Resources family

Kinds: any CRD-defined kind discovered via ADR-0052.

No additional items beyond the base set.

### Keyboard accelerators

The following table specifies the keyboard accelerator for each action item. An accelerator is a
single key pressed while the menu is open (not a global shortcut). All accelerators are lower-case
Latin letters unless otherwise specified.

- E — Edit YAML
- V — View Events
- Cmd-C — Copy Resource Link
- Y — Save YAML
- X — Delete
- S — Scale (Workloads family only)
- R — Rollout Restart (Workloads family only)
- L — View Logs (Pod only)
- T — Open Terminal (Pod only)
- F — Port Forward (Service and Pod only)
- U — View Subjects (RoleBinding and ClusterRoleBinding only)

No two items within the same family share an accelerator letter.

### Mutation guard integration

Each menu item that triggers a mutation delegates to the mutation guard defined in ADR-0012:

- Edit YAML — dispatches `#ApplyYAML`; requires single confirm with diff preview.
- Scale — dispatches `#ScaleReplicas`; requires single confirm.
- Rollout Restart — dispatches `#RolloutRestart`; requires single confirm.
- Delete — dispatches `#Delete`; requires double-confirm (`requiresDoubleConfirm: true`).
- Port Forward — dispatches `#PortForwardCreate`; not a cluster mutation; no confirm guard.
- View Logs, Open Terminal — read-only; no mutation guard.
- View Events, Copy Resource Link, Save YAML — read-only; no mutation guard.
- View Subjects — read-only navigation; no mutation guard.

### Detail drawer toolbar mirror

The detail drawer toolbar (ADR-0051) exposes the same action items for the selected resource.
When the detail drawer is open, invoking an action from the per-row 3-dot menu and invoking the
equivalent toolbar button in the drawer must produce identical outcomes. No action exists in the
drawer toolbar that is absent from the per-row menu of the same kind.

### Implementation notes

- The per-row 3-dot button must be keyboard-focusable and activatable with Space or Return.
- The menu must be implemented as a SwiftUI `Menu` view anchored to the 3-dot button.
- The `RowActionMenuBuilder` value type is responsible for constructing the menu item list for a
  given kind. It is initialised with the resource kind, the resource name, the namespace, and the
  operator's RBAC permissions. It returns an ordered array of `RowAction` values.
- `RowAction` is a `ValueObject` (DDD) carrying: `id` (stable string), `label`, `acceleratorKey`,
  `isMutating: Bool`, and `requiresDoubleConfirm: Bool`.
- `RowActionMenuBuilder` must be covered by unit tests asserting the exact item list per kind.

## Pros and cons of the options

### Option A — Per-kind freeform menus

- Good, because each list view can express only what is genuinely applicable with zero dead weight.
- Bad, because there is no shared keyboard accelerator contract and no shared code path.
- Bad, because operators building across-kind workflows cannot predict what is available.

### Option B — Per-family canonical menu (chosen)

- Good, because the family abstraction already exists in ADR-0050 and the sidebar tree.
- Good, because the base set is identical everywhere; family-specific additions are additive.
- Good, because hidden (not disabled) items keep sparse families uncluttered.
- Bad, because a new kind added to a family that does not fit the family's extension set requires
  an ADR amendment.

### Option C — Globally identical menu with disabled items

- Good, because every item is always visible, maximising discoverability.
- Bad, because Config and Storage families would display six disabled items on every row,
  degrading the menu signal-to-noise ratio.
- Bad, because VoiceOver narrates every disabled item, increasing cognitive load for screen reader
  users.

## Confirmation

- `RowActionMenuBuilder` unit tests cover every kind in every family, asserting the exact ordered
  item list, the correct `isMutating` flag, and the correct `requiresDoubleConfirm` flag.
- A Gherkin feature
  `docs/arch/contexts/resource_browser/features/row-action-menu-uniform.feature` covers the
  canonical menu shape per family, the delete double-confirm flow, keyboard accelerator dispatch,
  and hidden-item logic.
- A snapshot test captures the rendered menu for one representative kind per family to guard
  against accidental regression.
- The detail drawer toolbar tests (ADR-0051 Gherkin: `detail-drawer-toolbar-actions.feature`)
  are extended with a cross-reference assertion confirming that no toolbar button exists for an
  action that is absent from the per-row menu of the same kind.

## Followups

- ADR-0062 — Status chips and node conditions presentation: the row action menu for Node kind
  should eventually include Cordon / Uncordon (ADR-0012 mutation verbs); defer until ADR-0062
  decides the Node kind's family placement and canonical items.
- ADR-0066 — Floating action button for resource creation: the FAB triggers a create flow, not a
  per-row action; it is distinct from this ADR but the `RowAction` value type may be reused for
  the FAB's action dispatch.
- Once ADR-0067 decides whether to add an Applications root to the sidebar, the Applications
  family (Helm releases, ArgoCD Applications, Flux Kustomizations) will need a canonical menu
  addendum here.

## More information

- ADR-0012 — Mutating operations policy; defines the full mutation verb set, confirm requirements,
  and the `MutationGuardPort` contract that every mutating menu item must invoke.
- ADR-0050 — Resource navigation taxonomy; defines the six kind families used here as the primary
  partitioning scheme.
- ADR-0051 — Multi-cluster workspace; specifies the detail drawer toolbar that this ADR mirrors.
- ADR-0060 — Resource list export (CSV and YAML); defines Save YAML per row, cross-referenced as
  a base-set item here.
- `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md` — R25 identifies the
  per-row 3-dot action menu uniformity gap that this ADR closes.
