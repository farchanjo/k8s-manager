# K8sManager Spec Validation Pack

This document catalogues every validation surface in the spec, defines the three validation lanes,
and maps each lane to its CI invocation.

## Validation surfaces

### CUE schemas

Bounded-context schemas:

- `contexts/<bc>/schemas/*.cue` — one or more schema files per bounded context

Shared kernel schemas:

- `contexts/_shared/schemas/domain_events.cue`
- `contexts/_shared/schemas/shared_kernel.cue`

Bounded contexts with CUE schemas:

- `contexts/cluster_connectivity/schemas/` — auth_info, cluster, cluster_session,
  cluster_session_event, health_status, kubeconfig
- `contexts/context_navigation/schemas/` — active_context, recent_context
- `contexts/llm_provider/schemas/` — assistant_message, assistant_stream_event, provider_profile
- `contexts/assistant_chat/schemas/` — chat_message, chat_session
- `contexts/cluster_intelligence/schemas/` — mcp_invocation, mcp_tool_registry
- `contexts/local_persistence/schemas/` — keychain_entry, persistence_store, state_restoration
- `contexts/resource_browser/schemas/` — draft, editor_session, mutation_audit_entry,
  mutation_command, resource_browser_service, resource_descriptor, resource_view
- `contexts/port_forwarding/schemas/` — port_forward_event, port_forward_session
- `contexts/terminal_session/schemas/` — node_debug_descriptor, terminal_io_frame, terminal_session
- `contexts/helm_management/schemas/` — chart_metadata, release, release_history_entry
- `contexts/metrics_observability/schemas/` — curated_query_set, prom_query, prometheus_endpoint
- `contexts/analytics_dashboard/schemas/` — analytics_widget, dashboard, drilldown_event,
  scope_preset, widget_budget
- `contexts/app_shell/schemas/` — command_palette, design_tokens, i18n_manifest, icon_catalog,
  keyboard_shortcut_map, loading_state, locale_preference, menu_bar_tray, observable_state,
  self_monitoring, theme_preference, toast_notification, tray_metric_widget, tray_refresh_event,
  typography_preferences, window_layout

### Rego policies

Bounded-context policies:

- `contexts/cluster_connectivity/policies/kubeconfig_validation.rego`
- `contexts/cluster_connectivity/policies/subprocess_exec_allowlist.rego`
- `contexts/context_navigation/policies/navigation_policy.rego`
- `contexts/llm_provider/policies/provider_policy.rego`
- `contexts/assistant_chat/policies/chat_policy.rego`
- `contexts/cluster_intelligence/policies/tool_policy.rego`
- `contexts/local_persistence/policies/secret_redaction.rego`
- `contexts/resource_browser/policies/mutation_guard.rego`
- `contexts/port_forwarding/policies/port_forward_policy.rego`
- `contexts/terminal_session/policies/terminal_policy.rego`
- `contexts/helm_management/policies/release_decoder_invariants.rego`
- `contexts/metrics_observability/policies/metrics_policy.rego`
- `contexts/analytics_dashboard/policies/dashboard_policy.rego`

Shared policies (applied across all bounded contexts by conftest):

- `contexts/_shared/policies/` — base invariants shared by all BCs

### Gherkin feature files

Standard feature directory structure per bounded context:

- `contexts/<bc>/features/*.feature` — flat scenario files
- `contexts/<bc>/features/lifecycle/*.feature` — lifecycle scenarios
- `contexts/<bc>/features/chaos/*.feature` — failure-mode scenarios

Key feature sets:

- `cluster_connectivity/features/` — load-kubeconfig, probe-cluster-health,
  cluster-session-lifecycle; chaos/ (creds-expired, network-partition); lifecycle/
  (bookmark-event-handling, ca-bundle-rotation, cluster-session-lifecycle, cluster-unreachable,
  concurrent-cluster-sessions, creds-expired-mid-session, kubeconfig-swap-during-session,
  watch-relist-on-410)
- `resource_browser/features/` — apply-yaml-edit, browse-resources, contextual-actions,
  delete-with-double-confirm, json-editor, scale-and-restart, yaml-editor-realtime; lifecycle/
  (dirty-editor-recovery, double-confirm-delete, dry-run-budget-exhausted,
  mutation-confirmation-token-expired, secret-redaction-applied)
- `analytics_dashboard/features/` — cluster-overview, debug-timeline, latency-heatmap,
  pod-detail-debug, topology-graph
- `app_shell/features/` — accessibility, command-palette, diagnostics-export, icon-catalog,
  keyboard-shortcuts, loading-states, locale-selection, markdown-viewer,
  menu-bar-tray-energy-and-lifecycle, menu-bar-tray-live-metrics, menu-bar-tray-overview,
  onboarding, pluralization-and-formatting, progressive-disclosure, rtl-support,
  self-monitoring-diagnostics, state-driven-realtime, theme-and-typography, toast-notifications,
  window-layout, window-lifecycle

### DBML

- `contexts/local_persistence/schemas/storage.dbml` — SQLite DDL for all persistent tables (chat
  history, provider configuration, cluster-analysis cache, mutation audit, operator preferences)

### Structurizr DSL

- `architecture/workspace.dsl` — C4 workspace: System Context, Container, and Component views for
  every bounded context

### Lifecycle and event-flow documents

- `architecture/lifecycles/*.md` — per-bounded-context lifecycle diagrams (Mermaid state machine
  blocks)
- `architecture/event-flows.md` — cross-context domain event taxonomy and sequence diagrams

## Validation lanes

### Lane 1 — fast (~2s)

Static lint only. No external tool dependencies. Runs on every push and PR.

Checks executed:

1. GFM-table sentinel — reject any pipe-table row inside `docs/arch/`
2. MADR section-header conformance — assert four required `##` sections in every
   `decisions/adr-*.md`
3. DDD-role header — assert first line of every `.cue`, `.rego`, `.feature` file begins with
   `// DDD role:` or `# DDD role:`
4. kebab-case filename — assert no uppercase or underscore in any `.md` filename under `docs/arch/`

CI invocation:

```
bash scripts/validate-spec-fast.sh
```

Or via the user-global framework:

```
spec validate --lane fast
```

### Lane 2 — default (~10s)

All Lane 1 checks plus external tool validators. Runs on merge to main and nightly. Tools skip
gracefully when absent.

Additional checks:

5. `cue vet` — validate every `.cue` package in `contexts/`
6. `conftest parse` — Rego syntax and rule validation per bounded context
7. `gherkin-lint` — Gherkin syntax and structure; fallback regex when absent
8. `dbml2sql --postgres` — DBML round-trip lint for `storage.dbml`
9. `structurizr-cli validate` — DSL structural validation for `workspace.dsl`

CI invocation:

```
bash scripts/validate-spec.sh
```

Or via the user-global framework:

```
spec validate
```

### Lane 3 — full (~60s)

All Lane 2 checks plus render and integration synthesis. Not yet automated in CI; run manually
during architecture review cycles.

Additional steps:

- `structurizr-cli export -format mermaid` — export all views to Mermaid
- `mmdc` render — PNG/SVG output to `docs/arch/_rendered/`
- Integration mock — synthesize artefacts (CUE + Rego + Gherkin) and dry-validate that schema
  constraints are satisfiable end-to-end

Manual invocation:

```
bash scripts/render-diagrams.sh
```

Or via the user-global framework:

```
spec validate --lane full
```

## CI surface

The GitHub Actions workflow at `.github/workflows/spec-validate.yml` provides two jobs:

- `spec-validate-fast` — Lane 1. Triggered on every push and PR when any file under `docs/arch/` or
  `scripts/validate-spec*.sh` changes. No tool installation required. Fails the PR if any check
  fails.

- `spec-validate-full` — Lane 2. Triggered on push to `main` and on the nightly schedule (02:00
  UTC). Installs: `cue` (via go install), `conftest` (curl release), `gherkin-lint` (pnpm),
  `@dbml/cli` (pnpm). Go and pnpm binaries are cached across runs. Uploads validation logs and
  GFM-table diff as artefacts on failure (14-day retention).

## Tool dependencies

Tools required for Lane 2:

- `cue` — `go install cuelang.org/go/cmd/cue@latest`
- `conftest` — download from github.com/open-policy-agent/conftest/releases
- `gherkin-lint` — `pnpm dlx gherkin-lint`
- `dbml2sql` — `pnpm dlx @dbml/cli`
- `structurizr-cli` — download from github.com/structurizr/cli/releases (optional; step skipped when
  absent)

Tools required for Lane 3 (render):

- `mmdc` — `pnpm dlx @mermaid-js/mermaid-cli`
- `structurizr-cli` — required for Structurizr view export
