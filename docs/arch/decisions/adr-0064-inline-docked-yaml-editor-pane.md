# ADR-0064 — Inline docked YAML editor pane

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0030 (integrated multi-format editor), ADR-0050 (resource navigation taxonomy and
  multi-document tab system), ADR-0051 (multi-cluster workspace: cluster strip, provider grouping,
  chrome layout), ADR-0057 (bottom-docked terminal pane with node-debug shell integration)
- Tags — yaml-editor, docked-pane, inline-edit, app-shell, integrated-editor

## Context and problem statement

ADR-0030 defined the integrated multi-format editor as a `#EditorSession` AggregateRoot surfaced
inside a dedicated `DocumentTab` in the tab bar (ADR-0050). This covers deep, long-running edit
sessions where the operator intentionally leaves the resource list context. However, the reference
recording (`Screen Recording 2026-05-16 at 13.19.58.mov`, Lens × Mirantis Desktop, items R33/R34 in
`docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md`) shows a complementary
pattern: the YAML editor opens as a docked secondary pane below the resource list pane, not as a new
tab. The operator remains in the list context — the selected row stays highlighted, the detail drawer
remains accessible — while the editor occupies the lower portion of the content area.

The dedicated-tab model (status quo, Option A) is adequate for deep edits but breaks multi-resource
edit cadence: the operator must navigate away from the list, apply, navigate back, re-select the next
row, and repeat. The docked pane model eliminates the navigation overhead for quick single-field
corrections while preserving full `#EditorSession` semantics from ADR-0030.

This ADR defines:

- The layout host for the docked YAML editor pane.
- Pane chrome (drag-resize, breadcrumb, action buttons).
- The open/close lifecycle and its integration with the ADR-0030 apply path.
- Coexistence rules with the bottom-docked terminal pane (ADR-0057).
- The unsaved-changes guard.
- The toggleable diff overlay.

## Decision drivers

- **Preserve list context during quick edits** — operators correcting a single field across several
  resources must keep the list visible and the selected row highlighted while the editor is open.
- **Multi-resource edit cadence** — after a successful save the pane closes and the list refreshes
  the edited row in place, allowing the operator to immediately select the next resource without
  navigating back.
- **Undo isolation per pane** — the docked pane hosts its own `#EditorSession` with an isolated
  undo stack that does not interfere with any open editor tab for the same or another resource.
- **Reuse ADR-0030 apply path** — the docked pane is a presentation layer only; it reuses the
  ADR-0030 `DryRunApplyService`, `MutationDispatchService`, and confirmation modal without
  duplicating their logic.
- **Minimal layout regression** — the pane must not interfere with the cluster strip (ADR-0051),
  the detail drawer, or the bottom-docked terminal pane (ADR-0057).

## Considered options

- **Option A** — Editor as dedicated tab only (status quo, ADR-0030).
- **Option B** — Editor as docked pane below the list only; dedicated tab removed.
- **Option C** — Both: dedicated tab for deep edits initiated from the tab bar or the detail drawer
  toolbar's "Open in Tab" action, docked pane for quick edits initiated from the row action menu.

## Decision outcome

Chosen option — **Option C**, because:

- Option A requires navigation away from the list for every edit, breaking multi-resource edit cadence.
- Option B removes the dedicated tab that operators rely on for long-running, complex edits (deep
  Deployment spec rewrites, multi-field ConfigMap authoring, Markdown README edits) where the list
  context is irrelevant.
- Option C gives the operator the right surface for each job: the docked pane for quick,
  context-preserving edits; the dedicated tab for extended authoring sessions.

The "Edit YAML" row action menu item (ADR-0061 canonical shape) opens the docked pane. The "Open in
YAML Editor" detail drawer toolbar action (ADR-0051 §Detail drawer, action toolbar) opens the
dedicated tab. Both routes share the same `#EditorSession` domain type from ADR-0030.

### Pane chrome

The docked YAML editor pane occupies a horizontal split beneath the resource list pane inside the
content area column of the `NavigationSplitView`. Its chrome consists of:

- **Drag-resize handle** — a 4 pt horizontal handle strip at the top edge of the pane. Dragging the
  handle vertically resizes the pane. The pane persists its height in the per-cluster view state
  (ADR-0026 per-cluster view state JSON, key `dockedEditorPaneHeight`).
- **Default height** — 40 % of the content area height at first open. Minimum height: 200 pt.
  Maximum height: content area height minus 120 pt (leaving at least the list header and one row
  visible above the pane).
- **Fullscreen toggle** — a button at the top-right corner of the pane header that expands the pane
  to fill the full content area height, hiding the list above. Pressing the toggle again returns to
  the previous split height.
- **Breadcrumb** — a non-editable label in the pane header:
  `Editing kubernetes <Kind> <name> in namespace <ns>`. For cluster-scoped resources the namespace
  segment is omitted: `Editing kubernetes <Kind> <name>`. Kind is always capitalised as it appears
  in the Kubernetes API (e.g., `Deployment`, `ConfigMap`, `ClusterRole`).
- **Save button** — primary action button labelled "Save". Enabled when `isDirty == true` and the
  current `#EditorState` has zero `error`-severity diagnostics. Activating Save invokes the
  ADR-0030 apply pipeline (dry-run → diff preview → confirmation modal → SSA → audit log →
  outcome toast). On `#StateApplied(outcome: "succeeded")` the pane closes and the corresponding
  list row refreshes in place.
- **Discard button** — secondary action button labelled "Discard". Activating Discard when
  `isDirty == false` closes the pane immediately. When `isDirty == true` the unsaved-changes guard
  is triggered (see Unsaved-changes guard section below).
- **Diff toggle** — a toggle button labelled "Diff" in the pane header. When active, the editor
  splits horizontally into a side-by-side diff view: left pane shows the current server state
  (fetched via the ADR-0030 `DryRunApplyService` dry-run baseline), right pane shows the operator's
  edits. Removed lines are highlighted red; added lines are highlighted green; unchanged lines are
  collapsed with an expand affordance. The diff view is read-only on the left and editable on the
  right.
- **Line numbers** — always visible in the left gutter, consistent with the ADR-0030 editor
  component specification.

### Pane lifecycle

The docked YAML editor pane opens exclusively from the "Edit YAML" item in the per-row 3-dot action
menu (ADR-0061). The open sequence is:

1. Operator activates "Edit YAML" on a resource row.
2. `DockedEditorPaneOrchestrator` (an `ApplicationService`) checks whether a docked editor pane is
   already open for any resource.
   - If no pane is open: the pane slides up from the bottom of the content area with a spring
     animation (duration 0.25 s). The `#EditorSession` is created and the manifest loaded from the
     active watch stream (ADR-0034) or fetched via `KubernetesApiPort` if not cached.
   - If a pane is already open for a different resource and `isDirty == false`: the existing session
     is discarded and the new resource's manifest is loaded in place. The pane does not close and
     re-open; it updates in place.
   - If a pane is already open for a different resource and `isDirty == true`: the unsaved-changes
     guard is triggered. If the operator confirms discard, the new resource loads. If the operator
     cancels, the original resource remains loaded.
   - If a pane is already open for the same resource: no action; the pane is scrolled to the top and
     keyboard focus is moved to the editor.
3. The editor opens in `#StateIdle` (read-only). The keyboard shortcut `e` (ADR-0023) transitions
   the session to `#StateEditing`, or the operator may click anywhere in the editor content area.
4. On `Save`: the ADR-0030 apply pipeline runs. On `#StateApplied(outcome: "succeeded")`:
   the pane closes with a spring animation (0.25 s slide-down); the list row is refreshed.
5. On `Discard` (no unsaved changes) or `Escape` (twice, see below): the pane closes with the same
   slide-down animation.

### Unsaved-changes guard

When the operator activates "Discard" with `isDirty == true`, or presses `Escape` while
`isDirty == true`, a native `NSAlert`-style confirmation sheet is presented anchored to the pane:

- **Title** — "Discard changes?"
- **Message** — "Your edits to \<Kind\>/\<name\> have not been applied. Discard them?"
- **Buttons** — "Discard" (destructive) and "Keep Editing" (cancel).

Pressing `Escape` once while `isDirty == false` closes the pane immediately (equivalent to
"Discard" with no pending changes). Pressing `Escape` twice in rapid succession (within 500 ms) when
`isDirty == true` bypasses the sheet and discards immediately — consistent with the double-Escape
pattern used elsewhere in the application for emergency dismiss.

### Diff overlay

The diff overlay is toggled via the "Diff" button in the pane header or the keyboard shortcut
`⌘⇧D` while the pane has focus. The overlay uses the ADR-0030 `DryRunApplyService` dry-run
baseline as the server-state reference. If no dry-run result is available yet (e.g., the operator
has not made any changes since opening the pane), the left pane shows the manifest as loaded from
the watch stream cache.

The diff overlay does not affect the `#EditorState` machine; it is a purely presentational layer on
top of the existing editor session.

### Coexistence with the bottom-docked terminal pane

ADR-0057 defines a bottom-docked terminal pane that occupies the same vertical region beneath the
content list as this ADR's docked YAML editor pane. The two panes cannot be simultaneously visible:

- Only one docked pane can be open at a time per workspace window.
- When the operator opens the inline YAML editor pane while the terminal pane is visible and has
  `isDirty == false` (no unsaved edits) and no active PTY sessions: the terminal pane hides and the
  editor pane takes its position.
- When the operator opens the inline YAML editor pane while the terminal pane is visible and has one
  or more active PTY sessions: a non-blocking information banner appears at the top of the editor
  pane: "Terminal sessions are running in the background. Open terminal to resume." The terminal
  pane is hidden; sessions remain active in `TerminalSessionActor` but are not visible.
- When the operator opens the terminal pane (via the "Shell to Node" action or the terminal toolbar
  button) while the inline YAML editor pane is open and `isDirty == true`: the unsaved-changes guard
  is triggered. On operator confirmation of discard, the editor pane closes and the terminal pane
  opens.
- The operator can switch between the two panes at any time using the keyboard shortcuts defined in
  ADR-0057 (terminal) and the row action menu (editor). The most recently closed pane's last height
  is preserved in the per-cluster view state.

## Pros and cons of the options

Positive:

- Operators can perform quick YAML corrections without navigating away from the list view, reducing
  the round-trip cost of multi-resource edit cadence.
- The docked pane reuses the full ADR-0030 editor component (syntax highlighting, real-time
  validation, dry-run, diff preview, undo/redo, draft auto-save) without duplicating any domain
  logic.
- Undo isolation per pane prevents accidental cross-contamination between an open editor tab and
  the docked pane when both target the same resource.
- The coexistence rule with the terminal pane is deterministic and operator-controlled; no
  background pane switching occurs automatically.

Negative:

- `DockedEditorPaneOrchestrator` is a new ApplicationService that must coordinate between
  `OpenTabsActor` (ADR-0050), the list view state, and `TerminalSessionActor` (ADR-0057). Its
  implementation surface is wider than a simple view toggle.
- The one-pane-at-a-time rule means operators who want simultaneous terminal and YAML editing must
  use the dedicated editor tab, which breaks list context. A future ADR may revisit this if operator
  feedback requests both panes open simultaneously.
- Hiding the terminal pane on editor open can surprise operators who have active PTY sessions
  running. The information banner mitigates this but does not eliminate the discoverability concern.

## Confirmation

- Gherkin feature `docs/arch/contexts/app_shell/features/inline-docked-yaml-editor.feature`
  covers the five required scenarios: open pane from row action, save via ADR-0030 apply path,
  cancel with unsaved-changes guard, diff overlay toggle, and terminal/editor mutual exclusion.
- `DockedEditorPaneOrchestrator` unit tests assert the one-pane-at-a-time invariant against
  `TerminalSessionActor` (ADR-0057) and the unsaved-changes guard sheet presentation.
- A snapshot test captures the docked pane at default height, fullscreen, and diff-overlay
  states.
- The unsaved-changes guard is verified for both Discard-button activation and Escape-key
  dismissal, including the double-Escape bypass.
- The keyboard shortcut `⌘⇧D` for the diff overlay is verified against the ADR-0023 shortcut
  registry.

## Followups

- ADR-0065 (navigation history stack) should record "open docked editor pane for resource X" as a
  navigable history entry so that the back/forward arrows restore the pane state.
- ADR-0066 (floating action button) must clarify whether "Create new resource" from the FAB opens
  the docked editor pane (blank manifest) or a dedicated tab (new-resource tab). Recommended:
  dedicated tab for create, docked pane for edit-existing only.
- Once ADR-0057 is accepted, the coexistence interaction flow (mutual pane hiding with running PTY
  sessions) should be tested end-to-end with a scenario in
  `app_shell/features/bottom-docked-terminal-pane.feature` cross-referencing this ADR.

## More information

- ADR-0030 — `docs/arch/decisions/adr-0030-integrated-editor-md-yaml-json.md`
- ADR-0050 — `docs/arch/decisions/adr-0050-resource-navigation-taxonomy.md`
- ADR-0051 — `docs/arch/decisions/adr-0051-multi-cluster-workspace.md`
- ADR-0057 — `docs/arch/decisions/adr-0057-bottom-docked-terminal-pane.md`
- Gap analysis — `docs/arch/contexts/app_shell/feature-gap-analysis-lens-prism-ai.md` (R33, R34)
- Gherkin — `docs/arch/contexts/app_shell/features/inline-docked-yaml-editor.feature`
