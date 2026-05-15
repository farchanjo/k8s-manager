# Bounded Context — `app_shell`

## Purpose

Own the model of "how K8sManager presents itself to the operator on macOS". This context coordinates
window lifecycle, sidebar, menu bar, settings, and the surfacing of read models from the other
bounded contexts. It contains no business invariants of its own and declares no aggregates.

## Ubiquitous language

- **Main window** — the single primary window of the application. The MVP runs exactly one main
  window; multi-window navigation is out of scope.
- **Sidebar** — the left-hand panel listing pinned contexts at the top and the recents window
  beneath. Powered by `SidebarReadModel` from `context_navigation`.
- **Cluster health badge** — a status indicator rendered alongside each context in the sidebar.
  Powered by the `ClusterReadModel.lastHealth` field from `cluster_connectivity`.
- **Title bar** — the macOS-native window chrome. Displays the active context's display name from
  `ActiveContextReadModel`.
- **Settings surface** — the standard macOS Settings window (Command-comma). The MVP exposes only
  one setting: the KUBECONFIG override path. No telemetry or auto-update preferences in the MVP.

## Tactical roles

- No aggregates. The shell is a consumer.
- **`MainWindowCoordinator`** — DomainService (in this context loosely; it borders on
  infrastructure). Reacts to `ActiveContextChanged` and re-renders the title bar and main content
  area.
- **`SidebarPresenter`** — DomainService. Transforms `SidebarReadModel` into `SidebarViewState` for
  SwiftUI.
- **`SettingsCoordinator`** — DomainService. Surfaces the KUBECONFIG override and writes it back to
  the kubeconfig loader port hosted by `cluster_connectivity`.

## Dependencies

- Consumes `ActiveContextReadModel` and `SidebarReadModel` from `context_navigation`.
- Consumes `ClusterReadModel` and `KubeconfigLoadReportReadModel` from `cluster_connectivity`.
- Does not import `Yams`, `SwiftkubeClient`, or any I/O library. SwiftUI and AppKit are part of the
  macOS runtime, not infrastructure for the purposes of this layering.

## Read models exposed to other contexts

- None. The shell is a sink.

## Invariants

- The shell never reads kubeconfig files directly.
- The shell never invokes the Kubernetes API directly.
- The shell never holds credential material.

## Design system tokens

The app shell defines four categories of design token as CUE value objects in
`contexts/app_shell/schemas/`. They are resolved at launch by the ThemePreferenceService and
TypographyService and injected into the SwiftUI `Environment`. No view computes color, spacing, or
font properties directly.

`#ColorTokens` (design_tokens.cue) carries:

- **Brand palette** — `brandPrimaryLight` (#326CE5), `brandPrimaryDark` (#5E8FF0), `brandNavy`
  (#0F3074), `brandSky` (#9DB8E9). The CNCF palette (#0086FF) is explicitly rejected per ADR-0021.
- **Semantic surface tokens** — `surfaceBackground`, `surfaceElevated`, `accentBrand`. Each token is
  a `#ColorPair` with independent light and dark hex values stored in the SwiftUI Color Asset
  Catalog.
- **Semantic text tokens** — `textPrimary`, `textSecondary`, `textTertiary`.
- **Status tokens** — `statusHealthy`, `statusWarning`, `statusError`, `statusTerminating`,
  `statusUnknown`. Each passes 3:1 contrast against `surfaceBackground` in both appearances (WCAG
  AA).
- **Kind accent tokens** — `kindAccentPod` (blue), `kindAccentDeploy` (indigo), `kindAccentService`
  (teal), `kindAccentStorage` (purple), `kindAccentConfig` (brown), `kindAccentRBAC` (pink).

`#MaterialTokens` (design_tokens.cue) maps structural surface roles to SwiftUI `Material` values:
sidebar = `.sidebar`, content = `.regular`, inspector = `.thin`, popovers = `.ultraThin`, sheets =
`.thick`. Material assignments are fixed and not operator-configurable.

`#SpacingTokens` (design_tokens.cue) defines a 4-pt-base discrete scale [4, 8, 12, 16, 24, 32] with
semantic aliases (xsmall through xlarge). No intermediate values are permitted.

`#RadiusTokens` (design_tokens.cue) defines a discrete corner-radius scale [4, 8, 12] with semantic
aliases small/medium/large.

## Window layout

The primary window uses `NavigationSplitView` with three explicit columns. A `.inspector` panel is
toggled independently. A status bar is pinned at the bottom of the window below the split view.

```mermaid
graph TB
    subgraph MW["Main Window — .unifiedCompact toolbar"]
        direction TB
        TB["Toolbar (role: .editor, customizable)"]
        subgraph NSV["NavigationSplitView — 3 columns"]
            direction LR
            SC["Sidebar\n.sidebar material\n220–360 pt\ncontext list + badges"]
            CL["Content list\n.regularMaterial\n320–560 pt\nresources / chat / metrics"]
            DP["Detail pane\n.thinMaterial\n≥480 pt\nYAML / Events / Logs tabs"]
            SC --> CL --> DP
        end
        INS[".inspector\n.thinMaterial\nannotations / diff / theme prefs"]
        SB["Status bar\n.ultraThinMaterial\ncluster · namespace · sync · health"]
        TB --> NSV
        NSV --> INS
        NSV --> SB
    end
```

Column widths and panel visibility are persisted as `#WindowLayout` (window_layout.cue, DDD role
AggregateRoot) in the `local_persistence` bounded context and restored on every cold launch.

The toolbar uses `.windowToolbarStyle(.unifiedCompact)` with hidden title bar. The toolbar role is
`.editor`; the operator may customise toolbar items via the standard macOS customization sheet.

Detail pane tabs follow a fixed convention: Summary, YAML, Events for all resource kinds; Logs added
for Pod and Node; Terminal added for exec sessions.

Layering invariant: `AppShell` never reads kubeconfig files directly, never invokes the Kubernetes
API, and never holds credential material.

## Theme preference and configurability

The ThemePreferenceService resolves `#ThemePreference` (theme_preference.cue) on launch and exposes
the result through a SwiftUI `EnvironmentKey`. All operator-configurable knobs are exposed in
Settings > Appearance.

Configurable knobs:

- `colorScheme` — system / light / dark (default: system).
- `accentSource` — kubernetes_brand / system_tint (default: kubernetes_brand). When
  `kubernetes_brand`, the accent resolves to #326CE5 (light) or #5E8FF0 (dark). When `system_tint`,
  the accent follows `NSColor.controlAccentColor`.
- `uiDensity` — compact / comfortable / spacious (default: comfortable). Controls vertical padding
  rhythm in list rows and form controls.
- `sidebarDensity` — compact (28 pt rows) / regular (36 pt rows) (default: regular). Independent of
  `uiDensity`.
- `reduceMotion` — bool (default: false). Mirrors `accessibilityReduceMotion`; operator may override
  independently. When true or when the system flag is set, all transitions use
  `withAnimation(nil) {}`.
- `liquidGlassEnabled` — bool. Default true on macOS 26+, false on macOS 14/15. Setting is hidden on
  macOS 14/15. When false on 26+, eligible surfaces fall back to standard material treatment.

All knobs are persisted in `local_persistence` under the key `app_shell/theme_preference` with
schema version `v1` (`#ThemePreferenceV1`). Migrations are append-only.

## Typography

The TypographyService computes `#ResolvedTextStyle` records (typography_preferences.cue, DDD role
ReadModel) from the operator's `#TypographyPreferences` and injects them into the SwiftUI
environment. No view calls `Font.system` with hardcoded point sizes.

Font family assignment:

- SF Pro Display — all text at 20 pt and above (displayLarge, display, headline roles).
- SF Pro Text — all text at 19 pt and below (body, subheadline, callout, footnote, caption roles).
- Monospace family — YAML editor, log viewer, terminal panel. Default SF Mono; operator may switch
  to JetBrains Mono, Berkeley Mono, or IBM Plex Mono via Font Book. An unrecognised family name
  silently falls back to SF Mono.

Operator-configurable typography knobs:

- `uiScale` — small (0.875×) / medium (1.0×) / large (1.125×). Applied as a multiplier on top of
  Dynamic Type scaling.
- `monoFontFamily` — PostScript family name string. Validated at launch.
- `monoBaseSizePoints` — integer 10–16 pt (default 12). The uiScale multiplier is applied on top of
  this base.
- `useSystemDynamicType` — bool (default true). When true, text styles scale with the system
  accessibility font size preference.

The Clarity City font family is permanently rejected per ADR-0021. It is a CNCF marketing typeface
not optimised for dense information-display UI on macOS.

## Menu bar tray

The tray sub-domain owns the `NSStatusItem` installed in the macOS system menu bar, the `NSPopover`
that presents live cluster metrics to the operator, and the refresh lifecycle that drives all widget
data updates. It is implemented inside `app_shell` because it coordinates across the same set of
read models as the main window and shares design tokens, theme preferences, and the active context
signal from `context_navigation`.

### Tactical roles

- **`#MenuBarTray`** (AggregateRoot) — persisted snapshot of operator preferences (display mode,
  refresh interval, background refresh flag, popover pin flag) and the transient lifecycle state of
  the popover. Restored from `local_persistence` on cold launch under the key
  `app_shell/menu_bar_tray`.

- **`#TrayMetricWidget`** (ValueObject) — sum type representing one widget in the popover:
  `#SparklineWidget`, `#StackedBarWidget`, `#CountWidget`, `#RecentMutationsWidget`, or
  `#ActiveSessionsWidget`. Authored in the CUE schema; not mutated at runtime. The `TrayLayout`
  value object orders the active widgets.

- **`#TrayRefreshEvent`** (ValueObject) — sum type representing all discrete events in the refresh
  state machine: `#RefreshRequested`, `#RefreshSucceeded`, `#RefreshFailed`, `#RefreshPaused`,
  `#RefreshResumed`. Emitted as Combine Subject payloads; never persisted to disk.

- **`TrayRefreshScheduler`** (DomainService) — owns the interval timer (Combine
  `Timer.publish(every:)`), observes system signals (lid, low-power mode, NWPathMonitor), and emits
  `#TrayRefreshEvent` values. Manages the `#MenuBarTray.popoverState` transitions and controls
  subscription lifetime in response to `popoverDidClose`.

- **`TrayPresenter`** (DomainService) — transforms `#TrayRefreshEvent` values into widget view
  models. Issues PromQL queries through the `PromQueryAdapter` port and reads from Kubernetes-backed
  read models. Marks individual widgets as degraded when their query fails.

### Dependencies

- Consumes `ClusterReadModel` and `ActiveContextReadModel` from `context_navigation` for the active
  cluster identity and health badge.
- Consumes `PromQueryAdapter` port from `metrics_observability` for all Prometheus query_range and
  instant queries that drive sparklines, stacked bars, and count widgets.
- Consumes `MutationAuditReadModel` from `resource_browser` for the recent mutations widget.
- Consumes `ActivePortForwardsReadModel` from `port_forwarding` for the port-forward session count
  chip.
- Consumes `OpenTerminalsReadModel` from `terminal_session` for the terminal session count chip.
- Consumes `MCPInvocationLogReadModel` from `cluster_intelligence` for the active AI diagnostic
  trace chip.

### Refresh flow

```mermaid
sequenceDiagram
    participant Sched as TrayRefreshScheduler
    participant Pres as TrayPresenter
    participant MO as metrics_observability\nPromQueryAdapter
    participant KB as Kubernetes read models\n(resource_browser, port_forwarding,\nterminal_session)

    Sched->>Pres: RefreshRequested(cause)
    Pres->>MO: queryRange(promQLTemplate, range=60m)
    Pres->>KB: read MutationAuditReadModel(limit=5)
    Pres->>KB: read ActivePortForwardsReadModel
    Pres->>KB: read OpenTerminalsReadModel
    MO-->>Pres: PromQueryResult or PromQueryError
    KB-->>Pres: read model snapshots
    Pres->>Sched: RefreshSucceeded or RefreshFailed
    Sched->>Sched: update lastRefreshedAtRFC3339\non MenuBarTray aggregate
```

### Invariants

- The refresh scheduler never issues a Prometheus query on the main thread. All `URLSession` work
  happens on the `metrics_observability` background queue; results arrive via `AsyncStream` and are
  consumed with `await` in a detached Task bound to the widget's view model actor.
- No credential material (bearer tokens, kubeconfig paths, API server URLs with embedded secrets)
  appears in any `#TrayRefreshEvent` payload. The `reason` field of `#RefreshFailed` is stripped by
  the event producer before emission.
- The local rate limit is 1 outbound query per Prometheus endpoint per `refreshIntervalSeconds`. The
  `TrayPresenter` tracks in-flight query handles and drops duplicate requests that arrive within the
  same window.

### Settings keys

All tray preferences are persisted under `app_shell/menu_bar_tray` in `local_persistence`:

- `displayMode` — "active_cluster" | "all_clusters_summary"
- `refreshIntervalSeconds` — 5 | 15 | 30 | 60
- `manualRefreshOnly` — bool
- `backgroundRefreshEnabled` — bool
- `popoverPinned` — bool

## Command palette and keyboard shortcuts

Introduced by ADR-0023. The command palette is the single discoverable entry point for every
command, resource jump, namespace switch, and cluster switch in the application. It is activated by
`⌘P` (primary) or `⌘K` (alternate) from any screen state and provides fuzzy search across the full
command catalog, recent invocations (ring size 50), resource names, namespace names, and cluster
names simultaneously.

### Tactical roles

- **`#CommandPalette`** — AggregateRoot. Owns the lifecycle of the palette overlay, the
  recent-invocations ring, and the current query state. Persisted to `local_persistence` under
  `app_shell/command_palette/recent_invocations`. The ring stores only `commandId`, `invokedAt`, and
  `durationMillis` — no resource names, cluster names, or user-typed query strings.

- **`#CommandEntry`** — ValueObject. An immutable description of a single palette command:
  `commandId`, `title`, `subtitle`, `keyboardShortcut`, `scope`, `whenContext` predicate, and
  `requiresContext` flag. Declared statically in the CUE schema `command_palette.cue` and
  supplemented at runtime by entries registered from other bounded contexts.

- **`#ShortcutBinding`** — ValueObject. Maps a `keyChord` to a `commandId` within a `scope` (global,
  resource_browser, terminal). Carries a `whenContext` predicate string evaluated by
  `ShortcutScopeEvaluator` at key-press time against the current `ApplicationFocusSnapshot`.

- **`CommandResolverService`** — DomainService. Maintains the in-memory command catalog merged from
  the static `command_palette.cue` entries and runtime registrations from bounded contexts. Resolves
  a `commandId` to a callable handler. Detects conflicts at startup (fatal in debug, logged at error
  in release).

- **`ShortcutDispatchService`** — DomainService. Receives raw key events from the SwiftUI focus
  system, evaluates `#ShortcutBinding` entries against the current `ApplicationFocusSnapshot`, and
  dispatches matched commands to `CommandResolverService`. Single-key bindings (k9s-style: `l`, `s`,
  `d`, `e`, `u`) are evaluated only when the `ApplicationFocusSnapshot.focusedPanel` is
  `resourceBrowserListRow`.

### Command palette flow

```mermaid
sequenceDiagram
    actor Op as Operator
    participant SW as SwiftUI Window
    participant CP as CommandPalette
    participant Ranker as FuzzyRanker
    participant Preview as ActionPreview

    Op->>SW: Command-P or Command-K
    SW->>CP: openPalette(triggerSource)
    CP->>CP: loadRecentInvocations (ring 50)
    CP-->>Op: overlay visible, recent items shown, input focused

    Op->>CP: keystroke (incremental)
    CP->>Ranker: rank(query, catalog + recentInvocations)
    Ranker-->>CP: orderedResults [CommandEntry]
    CP->>Preview: previewFor(selectedEntry)
    Preview-->>Op: type-ahead action preview rendered

    Op->>CP: Return to invoke
    CP->>CP: recordInvocation(commandId, timestamp, duration)
    CP->>SW: executeCommand(commandId, context)
    CP-->>Op: overlay dismissed, focus returned to trigger
```

## Progressive disclosure

The three-layer disclosure model applies to all resource views across the application shell. Layer
transitions are driven by explicit operator gestures and are never triggered automatically.

- **Layer 1 — Overview KPIs** (always visible): aggregate health, pod ready counts, restart counts,
  age, and the five-color semantic status badge. Sidebar lazy-reveals resource kinds grouped by
  category; only the active group's kinds are expanded in the sidebar to avoid visual overload.

- **Layer 2 — Detail Panel** (on click or Return): events, conditions, owner references, and the RED
  method metrics panel (requests/errors left column, latency right column). Activated by clicking a
  list row or pressing Return when a row is selected.

- **Layer 3 — Config / YAML** (deliberate `⌘E` or `e` key): full YAML editor and advanced config
  controls. Only reachable from Layer 2 via an explicit gesture. The YAML editor is never opened
  automatically.

Sidebar lazy reveal: when the sidebar has more than twelve resource kinds in the current namespace,
kinds are grouped by category (Workloads, Networking, Configuration, Storage, RBAC, CRDs). Only the
active category is expanded. Expanding a category is a one-click gesture.

Power-user mode: when enabled in Settings > General, Layers 1 and 2 are collapsed into a single
dense list view that shows name, namespace, status, age, and resource-specific quick-stats in one
row. Power-user mode does not affect Layer 3 (YAML editor) access.

Layering invariant: `AppShell` never reads kubeconfig files directly, never invokes the Kubernetes
API, and never holds credential material. No layer transition may trigger an implicit mutation or a
read of credential material.

## Onboarding and accessibility

### First-launch tour

On cold start when no onboarding state is persisted, the application presents a three-step welcome
overlay: step 1 is a welcome message, step 2 guides the operator through importing a kubeconfig
file, and step 3 introduces the AI assistant with an example prompt. The tour can be skipped at any
step by pressing Escape. Onboarding state (complete or skipped) is persisted to `local_persistence`
under `app_shell/onboarding_state`. The tour is resumable from Settings > General via a "Restart
onboarding tour" action.

Empty states carry action hints: when the cluster list is empty the content area displays "Configure
your first cluster" with an "Add cluster" action button. When the LLM provider has no key configured
and the operator adds one, a "Try a prompt" CTA appears pointing to the assistant chat panel.

The first time the operator initiates a mutating operation, a one-time modal explains the mutation
safety policy as specified in ADR-0012. The operator must acknowledge before the mutation flow
proceeds. This modal is presented exactly once per installation.

### Keyboard-only navigation

The full application shell is navigable without a pointer device. Tab and Shift-Tab traverse all
interactive elements in DOM order. Arrow keys navigate within list and sidebar rows. Return
activates the focused element. Escape closes overlays and returns to the previous state. `⌘P` opens
the command palette from any focused element. All palette result rows, sidebar items, and resource
list rows are keyboard-focusable and activatable with Return.

### VoiceOver labels

Every widget in the shell declares an `accessibilityLabel`. Cluster health badges announce cluster
name and health status. Resource list rows announce kind, name, namespace, and status. The command
palette overlay declares `accessibilityLabel("Command Palette")` and traps focus within the overlay
while open. Result rows announce title, subtitle, and keyboard shortcut. The type-ahead preview
region posts an `accessibilityAnnouncement` on each result-set change.

### WCAG AA target

All text tokens defined in `design_tokens.cue` achieve a minimum 4.5:1 contrast ratio against their
background surface token in both Light and Dark appearances. Status tokens achieve at least 3:1
against the `surfaceBackground` token in both appearances. When the operator enables Increase
Contrast (Increased Contrast mode), the brand accent token is replaced with a higher-contrast
variant. All interactive element borders receive increased opacity in Increased Contrast mode.

### Reduce motion

When `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is true, or when the `reduceMotion`
knob in the `#ThemePreference` schema is set to true, all panel open/close transitions and
disclosure-layer transitions are immediate — no spring animation, no opacity crossfade, no
transform. The operator may set the `reduceMotion` knob independently of the system flag; the system
flag takes precedence when it is true.

## App self-monitoring

Introduced by ADR-0027. K8sManager monitors its own process-level and session-level resource
consumption and exposes the data in three surfaces: Settings → Diagnostics (live counters and
sparklines), the menu bar tray (opt-in widget), and the analytics dashboard (`SelfMonitoring` scope,
ADR-0024).

### Tactical roles

- **`#SelfMonitoringState`** — AggregateRoot. Persists operator preferences: sample interval, tray
  surface toggle, ring-buffer retention, and export-enabled flag. Restored from `local_persistence`
  under `app_shell/self_monitoring_state`.

- **`#SelfMetricSample`** — Entity. One snapshot collected at a single timestamp. Carries 17 fields
  covering CPU, memory, threads, file descriptors, network I/O, active Kubernetes sessions, SQLite
  and cache sizes, Swift actor count, and SwiftNIO event loop group count.

- **`#DiagnosticsBundle`** — ValueObject. Metadata record embedded as `bundle-manifest.json` inside
  every exported diagnostics zip. Created by `DiagnosticsBundleExporter`; never mutated after the
  bundle is sealed.

- **`SelfMonitoringSampler`** — DomainService. Polls Darwin APIs (`mach_task_info`, `TASK_VM_INFO`,
  `proc_pidinfo`) and instrumented atomic counters on the configured interval (default 5 s). Feeds
  the in-memory ring buffer (default 60 min).

- **`DiagnosticsBundleExporter`** — DomainService. Packages the 24 h SQLite history of
  `#SelfMetricSample` records and sanitized log files into a zip at `~/.config/k8smanager/exports/`.
  Runs the log redactor before sealing; aborts on any redaction failure (fail-safe).

### Data flow

```mermaid
graph LR
    Darwin["Darwin APIs\nmach_task_info / TASK_VM_INFO\nproc_pidinfo"]
    Counters["Instrumented counters\nwatch/exec/pf/chat/actor/kqueue"]
    Sampler["SelfMonitoringSampler"]
    Ring["MetricsBuffer\n(ring 60 min + SQLite 24 h)"]
    DiagView["Settings → Diagnostics\nlive counters + sparklines"]
    TrayW["Tray widget\n(opt-in)"]
    AnalyticsS["Analytics dashboard\nSelfMonitoring scope"]
    Exporter["DiagnosticsBundleExporter"]
    Zip["exports/*.zip"]

    Darwin --> Sampler
    Counters --> Sampler
    Sampler --> Ring
    Ring --> DiagView
    Ring --> TrayW
    Ring --> AnalyticsS
    Ring --> Exporter
    Exporter --> Zip
```

### Invariants

- The sampler never uploads metric data over the network.
- The exporter aborts the entire export if any log-redaction step fails; no partial bundle is
  written.
- Metrics that are unavailable in the App Sandbox degrade to the sentinel value `−1` and are
  rendered as "unavailable" in the UI; they never cause a crash or an invalid sample record.

## Iconography (SF Symbols + custom set)

Governed by ADR-0028 — SF Symbols and native iconography (refines ADR-0021). All symbol references
in `app_shell` views are declared in the `#IconCatalog` ValueObject
(`contexts/app_shell/schemas/icon_catalog.cue`). No view may use a symbol name that is not
catalogued there.

### Tactical roles

- **`#IconCatalog`** (ValueObject) — the canonical registry of all symbol references. Each entry
  carries: `id` (kebab-case slug), `symbolName` (SF Symbols stock name or `k8s.*` custom name),
  `renderingMode`, `variant`, `accessibilityLabel`, `semantic` tag, and `isCustomSymbol` flag. CUE
  constraints enforce non-empty labels and the `k8s.` prefix for custom symbols.

- **`IconResolver`** (DomainService) — translates an `#IconCatalog` slug to a fully-resolved
  `#SymbolRenderHint` at render time. Reads `#ColorTokens` from the design token registry to
  populate palette layer tints. Checks `#available(macOS 15, *)` and falls back to
  `macOS14FallbackName` when present.

### Rendering pipeline

```mermaid
graph LR
    A["Catalog id\n(slug)"] --> B["IconResolver\n(DomainService)"]
    B --> C{"isCustomSymbol?"}
    C -- "false" --> D["Image(systemName:)\nSF Symbols 6 stock"]
    C -- "true" --> E["Image(symbolName:)\nk8s.* .symbolset\nin Assets.xcassets"]
    D --> F["IconView wrapper"]
    E --> F
    F --> G[".symbolRenderingMode()"]
    G --> H[".foregroundStyle()\nfrom #ColorTokens"]
    H --> I[".accessibilityLabel()\nfrom #IconCatalog"]
    I --> J{"animation?"}
    J -- "none" --> K["Static glyph"]
    J -- "pulse/bounce/variableColor" --> L[".symbolEffect()\n(suppressed if reduceMotion)"]
    L --> K
```

### Custom symbol set

Kubernetes-specific kinds that have no adequate SF Symbols stock mapping are authored as custom
`.symbolset` assets embedded in `Assets.xcassets`:

- **`k8s.pod`** — Pod (cubic outline). Bundle-embedded.
- **`k8s.deployment`** — Deployment (arrows-around-squares). Bundle-embedded.
- **`k8s.statefulset`** — StatefulSet (ordered stack). Bundle-embedded.
- **`k8s.daemonset`** — DaemonSet (broadcast glyph). Bundle-embedded.
- **`k8s.helm.wheel`** — Helm release / app icon (7-spoke wheel). Bundle-embedded.

All custom symbols are designed to the SF Symbols Regular weight template and support Regular,
Semibold, and Bold weight variants. They are available offline without any network request.

### BDD coverage

`icon-catalog.feature` covers: kind consistency across sidebar / list / detail header; status fill
variants in the ApiServerHealth widget; palette layer contrast in light and dark appearances;
offline availability of custom symbols; accessibility label presence at every call site;
`symbolEffect(.pulse)` for pending state with reduce-motion suppression.

## Internationalisation (i18n) and multi-language support

Governed by ADR-0033. The app shell owns the locale resolution lifecycle, the operator-facing locale
picker in Settings → Language, and the persistence of `#LocalePreference` to `local_persistence`
under the key `app_shell/locale_preference`.

All user-visible UI strings originate in en-US and are localised via Xcode String Catalog
(`.xcstrings`, macOS 14+ native format). The MVP+ baseline ships three locales: `en` (en-US +
en-GB), `pt-BR`, and `es-ES`. Additional locales may be contributed by community via PR; the
governance contract is `i18n_manifest.cue`.

### Tactical roles

- **`#LocalePreference`** (ValueObject) — the operator's persisted locale settings:
  `localeIdentifier`, `followSystem`, `dateStyle`, `timeStyle`, `timezone`, `numberFormat`,
  `layoutDirection`, and optional `pluralizationRule`. Defined in
  `contexts/app_shell/schemas/locale_preference.cue`.

- **`#LocaleManifest`** (ValueObject) — shape of the locale registry; canonical instance is
  `i18nManifest` in `contexts/app_shell/schemas/i18n_manifest.cue`. Carries `sourceLocale`,
  `baselineLocales`, and `extensionLocales`.

- **`#TranslatableKey`** (ValueObject) — documentation and lint schema for individual `.xcstrings`
  keys; records `keyPath`, `englishSource`, `contextHint`, and plural variant map. Defined in
  `i18n_manifest.cue`.

- **`LocaleResolverService`** (DomainService) — resolves the active `Locale` at launch and on
  operator override. Reads `#LocalePreference` from the persistence port; falls back to
  `Locale.preferredLanguages[0]`; ultimate fallback is `en-US`. Sets the SwiftUI `\.locale` and
  `\.layoutDirection` environment values reactively. Locale changes take effect within 200 ms
  without application restart.

- **`TranslationCatalogPort`** (Port) — an abstraction over the `.xcstrings` bundle look-up. Allows
  injection of a test double with pre-seeded key translations in unit and integration tests without
  requiring the full Xcode bundle pipeline.

### i18n data flow

```mermaid
graph LR
    LP["LocalePreferencePort\n(local_persistence)"]
    SYS["Locale.preferredLanguages\n(macOS system)"]
    LRS["LocaleResolverService\n(DomainService)"]
    ENV["SwiftUI Environment\n\\.locale\n\\.layoutDirection"]
    XCS[".xcstrings bundle\n(all locale variants)"]
    TCP["TranslationCatalogPort\n(Port)"]
    VIEW["SwiftUI Views\nText(key)\n/ String(localized:)"]
    FB["en-US fallback\n(missing key)"]

    LP --> LRS
    SYS --> LRS
    LRS --> ENV
    ENV --> VIEW
    XCS --> TCP
    TCP --> VIEW
    VIEW --> FB
```

### Community extension model

Any Apple-recognised locale may be added by a community contributor via a PR that satisfies the lint
contract in `i18n_manifest.cue`: at minimum 75% `translationCoverage`, a `displayName` in the target
locale's own script, a GitHub `maintainer` handle, and an accurate `status` (`"beta"` or
`"incomplete"`). The core team reviews only structural correctness; linguistic quality is the
community maintainer's responsibility.

Extension locales with `translationCoverage < 0.80` display a warning badge in the Settings →
Language picker. Locales with `status: "incomplete"` show a banner when active. Missing keys always
fall back to the en-US source string — never blank, never the raw key identifier.

Fifteen extension locales are pre-registered in `i18n_manifest.cue` with `status: "incomplete"` and
`translationCoverage: 0.0` to reserve identifiers and signal intent: pt-PT, es-MX, es-AR, fr-FR,
de-DE, it-IT, nl-NL, pl-PL, ru-RU, ja-JP, ko-KR, zh-Hans, zh-Hant, ar, and he. The `ar` and `he`
locales additionally serve as RTL layout test targets during development.

### RTL invariant

YAML, JSON, log, and terminal views override `\.layoutDirection` to `leftToRight` unconditionally.
RTL layout mirroring applies to all navigational chrome (sidebar, content list, detail pane,
toolbar) and to directional SF Symbols but never to code-display surfaces.

## Async resource states and loading UX

Governed by ADR-0031 — Loading states and async resource UX.

Every async operation that affects UI state is represented as an `AsyncResource<T>` Swift enum with
four cases: `idle`, `loading`, `success`, and `failure`. All views that load data follow this
contract and render the appropriate presentation mode:

- `skeleton` — structural placeholder using `.redacted(reason: .placeholder)` for operations whose
  layout is known and expected duration >100 ms.
- `shimmer` — skeleton with a diagonal gradient animation for content-heavy or layout-unknown
  surfaces.
- `spinner` — indeterminate `ProgressView` for quick operations <500 ms.
- `progressBar` — determinate `ProgressView` when total units are known.

A 200 ms throttle prevents idle → loading transitions from flashing for operations that resolve
quickly (e.g., warm SQLite reads). Empty states with action hints and error states with Retry
buttons complete the UX surface.

CUE schema: `contexts/app_shell/schemas/loading_state.cue` BDD coverage:
`contexts/app_shell/features/loading-states.feature`

## Toast notifications

Governed by ADR-0032 — Toast notification system.

A global `ToastStack` aggregate (floating `bottom_right` overlay) is the single surface for all
operation feedback. Every domain event that the operator needs to be aware of — mutation success,
connection failure, kubeconfig reload, port-forward open — emits a `#Toast` via the `ToastEmitter`
domain service.

### Tactical roles

- **`#ToastStack`** (AggregateRoot) — owns active toasts (max 5) and the overflow queue. Position
  operator-configurable. Persisted to `local_persistence` under `app_shell/toast_stack`.
- **`#Toast`** (ValueObject) — immutable card with id (UUIDv7), title, message, severity, icon,
  `autoDismissMs`, `pinned`, and optional `#ToastAction`.
- **`ToastEmitter`** (DomainService) — assigns UUIDv7, computes `autoDismissMs` from severity,
  enqueues to `#ToastStack`, and writes to the `toast_history` SQLite table.
- **`ToastDismissScheduler`** (DomainService) — runs the per-toast auto-dismiss timer on
  `@MainActor`, honours the `pinned` flag, and pauses timers while the pointer hovers over the
  stack.

### Toast emit flow

```mermaid
sequenceDiagram
    participant DL as Domain Layer
    participant TE as ToastEmitter
    participant TS as ToastStack
    participant DB as PersistenceActor
    participant UI as SwiftUI overlay

    DL->>TE: emitToast(title, severity, action?)
    TE->>TS: enqueue(#Toast)
    TS-->>UI: @Observable change → re-render
    TE->>DB: insert toast_history row
    UI-->>TS: auto-dismiss after autoDismissMs
    TS->>DB: update dismissed_at_rfc3339
```

CUE schema: `contexts/app_shell/schemas/toast_notification.cue` BDD coverage:
`contexts/app_shell/features/toast-notifications.feature`

## State-driven realtime UI

Governed by ADR-0034 — State-driven realtime UI architecture.

All SwiftUI views are pure functions of `@Observable` view model properties. The Observation
framework (Swift 5.9+ `@Observable` macro) is the exclusive reactivity mechanism — no Combine, no
`ObservableObject`, no `@Published` in new code.

Domain ports expose live data as `AsyncThrowingStream<Event, Error>`. View models consume the stream
with a `for try await` loop inside a `Task { @MainActor in … }` and mutate `AsyncResource<T>` state
on each received event. SwiftUI's `withObservationTracking` granular change tracking re-renders only
the views that read the changed property.

No polling. No manual refresh button in primary resource views. Cancellation propagates via Swift
structured concurrency: `task.cancel()` reaches the `AsyncThrowingStream` `onTermination` handler,
which closes the Kubernetes HTTP/2 watch channel.

CUE schema: `contexts/app_shell/schemas/observable_state.cue` BDD coverage:
`contexts/app_shell/features/state-driven-realtime.feature`

## Out of scope

- Resource browsing, Helm, dashboards, telemetry, auto-update surfaces. These will arrive in later
  milestones and will each introduce their own bounded contexts or extend `app_shell`.
