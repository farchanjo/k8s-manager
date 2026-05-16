# Feature gap analysis — K8S-Manager vs Lens × Mirantis Prism AI

- Status — Draft (analysis, awaiting ratification into ADRs and Gherkin features)
- Date — 2026-05-16
- Author — Fabricio Fonseca
- Source artifact — `Screen Recording 2026-05-16 at 13.19.58.mov` (Lens × Mirantis Desktop with
  Prism AI assistant, recorded 2026-05-16, 117 seconds @ 3840×2160, 50 fps, H.264, ReplayKit)
- Related contexts — `app_shell`, `cluster_connectivity`, `context_navigation`, `resource_browser`,
  `metrics_observability`, `helm_management`, `port_forwarding`, `terminal_session`,
  `local_persistence`, `assistant_chat`
- Related ADRs — ADR-0013 (resource browser scope), ADR-0021 (app shell design system),
  ADR-0030 (integrated editor), ADR-0050 (resource navigation taxonomy),
  ADR-0051 (multi-cluster workspace), ADR-0052 (custom resource discovery),
  ADR-0053 (global namespace filter)

## 1. Purpose

This document captures a feature-by-feature reading of the reference recording of Lens × Mirantis
Desktop running its Prism AI assistant against four real clusters (AKS, EKS, two local kubeconfigs
including DigitalOcean DOKS clusters). The goal is to determine which capabilities are already
specified or implemented in K8S-Manager, which are partially covered, and which are entirely
absent. The output of this document feeds new ADR drafts and Gherkin features that close the gaps.

This document is descriptive, not prescriptive. It does not propose a final implementation
ordering; it inventories the surface area observed in the recording, maps it to the present spec
and source tree, and flags every unsatisfied item.

## 2. Method

- The video was probed with `ffprobe` (h264 / 3840×2160 / 117 s).
- Frames were extracted at 0.33 fps (one every 3 seconds, 39 frames total) and rescaled to 1920 px
  width with `ffmpeg -vf "fps=1/3,scale=1920:-1"`.
- Each frame was inspected. Distinct interaction states observed: Welcome tab, Nodes list with
  detail drawer, Secrets list with inline YAML editor, Custom Resource Definitions listing,
  Custom Resources expanded sidebar tree, Persistent Volumes list with detail drawer, inline
  bottom-docked terminal connected to a node, Node detail with embedded Prometheus chart and
  process listing (`top`).
- The K8S-Manager source tree under `project/Sources/` and the spec tree under `docs/arch/` were
  cross-referenced. Every observed feature was matched against existing ADRs (53 total at time of
  writing), Gherkin features under `docs/arch/contexts/<ctx>/features/`, and Swift modules.

## 3. Reference UI catalogue (Lens × Mirantis Prism AI)

The recording surfaces the following capabilities. Each entry is numbered for traceability in the
gap matrix in section 5.

### 3.1 Chrome and workspace layout

- **R1** — Vertical cluster strip at the left extreme of the window with circular avatar chips
  (initials + provider-derived color), active-chip highlight, status ring (green when connected),
  hover tooltip with cluster display name.
- **R2** — Top-of-window tab strip with closable tabs, an `+` to open new tabs, scroll
  affordances when overflowing, and a "Welcome" tab always available at the leftmost position
  on first launch.
- **R3** — Top-right chrome: Prism AI assistant brand button, notifications bell, user avatar
  menu.
- **R4** — Top-left chrome: history back/forward arrows (page-level browser-style navigation).
- **R5** — Bottom status bar: active cluster context label plus version (e.g. "EONF Services
  (v1.33.1)"), support link at the right edge.
- **R6** — `NavigationSplitView`-style three columns: navigator (sidebar tree), content list,
  detail drawer (right slide-in).
- **R7** — Bottom-docked, drag-resizable, multi-tab terminal pane that slides up from the bottom
  of the content area, with fullscreen toggle and per-tab search.

### 3.2 Cluster acquisition and provider grouping

- **R8** — Welcome screen with five start actions: Open Onboarding Wizard, Add Kubeconfig from
  clipboard, Add Kubeconfig from filesystem, Add Clusters from AWS, Add Clusters from AKS. The
  Welcome screen also exposes "Useful Guides" links (Getting Started, Using Prism AI, Getting
  Support).
- **R9** — First-launch onboarding wizard (three-step welcome sequence with progress indicator).
- **R10** — Add Kubeconfig from clipboard: paste YAML directly without writing a file.
- **R11** — Add Kubeconfig from filesystem: native file picker.
- **R12** — AWS cluster discovery: list EKS clusters reachable with current AWS credentials and
  import their kubeconfig entries.
- **R13** — AKS cluster discovery: list Azure clusters reachable with current Azure credentials.
- **R14** — Provider grouping in the sidebar cluster taxonomy: top-level sections AKS, EKS,
  Local Kubeconfigs (and implicitly GKE, OIDC). Local Kubeconfigs is a heterogeneous group that
  contains DigitalOcean DOKS, kind, k3d and any kubeconfig without a recognised exec block.
- **R15** — Per-cluster status dot (green/red/grey/amber) in the sidebar tree next to the cluster
  display name.

### 3.3 Sidebar tree and resource taxonomy

- **R16** — Per-cluster category tree with disclosure states: Overview, Applications, Nodes,
  Workloads, Config (Config Maps, Secrets, Resource Quotas, Limit Ranges, Horizontal Pod
  Autoscalers, Pod Disruption Budgets, Priority Classes, Runtime Classes, Leases, Mutating
  Webhook Configurations, Validating Webhook Configurations), Network (Services, Endpoint
  Slices, Endpoints, Ingresses, Ingress Classes, Network Policies, Port Forwarding), Storage
  (Persistent Volume Claims, Persistent Volumes, Storage Classes), Namespaces, Events, Helm,
  Access Control, Custom Resources (Definitions plus dynamic per-API-group subtree), Security
  Center.
- **R17** — Custom Resources expanded subtree lists every API group with at least one CRD
  installed in the cluster, sorted alphabetically (acme.cert-manager.io, agent.k8s.elastic.co,
  apm.k8s.elastic.co, apps.kruise.io, argoproj.io, autoscaling.k8s.elastic.co, beat.k8s.elastic.co,
  bitnami.com, cert-manager.io, cilium.io, core.strimzi.io, databases.spotahome.com,
  dataplane-operator.doks.digitaloc.com, elasticsearch.k8s.elastic.co,
  enterprisesearch.k8s.elastic.co, extensions.istio.io, externaldns.k8s.io, flink.apache.org,
  gateway.networking.k8s.io, k8s.keycloak.org, kafka.strimzi.io, kibana.k8s.elastic.co,
  logstash.k8s.elastic.co, maps.k8s.elastic.co, minio.min.io, monitoring.coreos.com,
  monitoring.grafana.com, networking.istio.io, policy.kruise.io, postgresql.cnpg.io,
  psmdb.percona.com, rabbitmq.com, ray.io, registry.apicur.io, security.istio.io,
  snapshot.storage.k8s.io, spark.apache.org, stackconfigpolicy.k8s.elastic.co, starrocks.com,
  sts.min.io, telemetry.istio.io, velero.io).
- **R18** — Each API group expands to a list of kinds (e.g. extensions.istio.io contains
  Wasm Plugin; externaldns.k8s.io contains DNS Endpoint).
- **R19** — A `TEAMWORK` section appears at the bottom of the navigator (collapsed in the
  recording). This is Lens-proprietary team collaboration (shared sessions, presence) and is
  classified out of scope for K8S-Manager.

### 3.4 Resource list views

- **R20** — Column-sortable, virtualised list per kind with checkbox bulk-select, kind-specific
  columns (Nodes shows Name, CPU mini-bar, Memory mini-bar, Disk mini-bar, Taints, Roles, Version,
  Age, Conditions chip; Secrets shows Name, Namespace, Labels, Keys, Type, Age).
- **R21** — Mini bars per node row showing live CPU / Memory / Disk usage relative to capacity,
  with colour-coded segments (blue / pink / amber) that animate as values change.
- **R22** — Per-list namespace selector (top of the list). Defaults to "Select Namespace"
  meaning "All". Special: cluster-scoped kinds show no namespace selector. CRD list shows an
  "All groups" filter dropdown instead.
- **R23** — Per-list text search with case-sensitive and regex toggles (`Aa` / `.*` controls).
- **R24** — Per-list item count badge and a download icon next to it that exports the visible
  list (CSV; YAML for individual items via the row action menu).
- **R25** — Per-row 3-dot action menu (edit YAML, delete, view events, copy resource link).
- **R26** — Conditions chip in node rows ("Ready" green pill, "NotReady" red pill, etc.).
- **R27** — Resource counts in the bottom-right of certain panels (live `<n> items`).
- **R28** — Floating action button (FAB, blue `+` circle at the bottom-right of the list pane)
  for create-resource workflows.

### 3.5 Detail drawer

- **R29** — Right slide-in detail drawer with header (kind, name), close X, and per-kind action
  toolbar in the upper-right corner (Shell-to-Pod, Edit YAML, Logs, Delete, etc.).
- **R30** — Node detail drawer sections: Metrics chart (Prometheus-backed CPU usage, requests,
  allocatable, capacity over a configurable time range with hover tooltip and X-axis tick
  marks), Properties (Created, Name, Labels disclosable, Annotations disclosable, Addresses
  Internal/Hostname/External, OS, OS Image, Kernel version, Container runtime, Kubelet version,
  Conditions), Capacity (CPU, Memory, Ephemeral Storage, Hugepages-1Gi, Hugepages-2Mi, Pods),
  Allocatable (same shape as Capacity but smaller), Pods running on node (table with Name, Node,
  Namespace, Ready, CPU, Memory, Status), Events (or "No events found").
- **R31** — PersistentVolume detail drawer sections: Properties (Created, Name, Annotations,
  Finalizers, Capacity, Access Modes, Reclaim Policy, Storage Class Name, Status, Volume Mode),
  Provider (Source Provider, Driver, storage.kubernetes.io/csi…, FS Type, Read Only), Claim
  (Type, Name with click-through navigation, Namespace), Events.
- **R32** — Secret detail drawer sections: Properties (Created, Name, Namespace, Annotations
  disclosable, Type), Events, Data (per-key reveal/hide toggle with eye icon, copy-to-clipboard,
  edit inline). For `kubernetes.io/dockerconfigjson` the rendered value is the parsed JSON with
  hide button labelled "Hide".
- **R33** — Inline YAML editor opens in a docked secondary pane (bottom split) with line
  numbers, syntax highlighting, breadcrumb "Editing kubernetes <Kind> <name> in namespace
  <ns>", and a save button.
- **R34** — "Save" applies the YAML via PATCH; cancel discards. ADR-0030 / ADR-0012 already
  define this contract; the docked secondary-pane positioning is the new requirement.

### 3.6 Terminal and node debugging

- **R35** — "Shell to Node" link in the node detail drawer header that opens a node debug shell
  in the bottom-docked terminal pane.
- **R36** — Bottom-docked terminal pane is multi-tab (e.g. "Node: cpu-optimized-kisct"), with
  add-tab `+`, close X per tab, search across visible output, fullscreen toggle, and
  drag-resizable height.
- **R37** — Connection status banner in the terminal pane ("Shell to Node: <name>", then
  `Connecting …`, then live PTY).

### 3.7 Assistant and notifications

- **R38** — Prism AI brand button in the top-right chrome (entry point to the assistant slide-out
  panel).
- **R39** — Notifications bell in the top-right chrome with badge counter for unread items.

### 3.8 Navigation primitives

- **R40** — Browser-style back/forward navigation history (per-window or per-tab) shown as
  top-left arrow buttons.
- **R41** — Home dropdown in the navigator header (`Home` label with a chevron) — a workspace
  scope selector (per-organisation or per-project filtering). Out of scope for K8S-Manager;
  noted for completeness.

## 4. Current K8S-Manager state

### 4.1 ADRs already covering reference items

- ADR-0013, ADR-0050 — resource kind taxonomy (51 standard kinds; 7 of the 11 Config kinds
  enumerated; matches R16 except `ServiceAccount` belongs to "Access Control" in the reference
  and to "Config" in ADR-0050).
- ADR-0051 — vertical cluster strip with provider grouping, status ring, detail drawer chrome,
  status bar, top-right chrome region; covers R1, R3, R5, R6, R14, R15.
- ADR-0050 — multi-document tab bar with `OpenTabsActor`, persistence across launches, watch
  ownership; covers R2 partially (no Welcome tab handling specified).
- ADR-0030 — integrated editor for YAML / JSON / Markdown / TOML; covers R33 contract but
  positions the editor inside a dedicated tab rather than as a docked secondary pane attached to
  a list (R33 is a presentation-positioning gap).
- ADR-0052 — custom resource discovery with dynamic sidebar grouping; covers R17, R18.
- ADR-0053 — global namespace filter scoped per cluster, propagated to lists via SwiftUI
  `Environment`; covers R22.
- ADR-0021, ADR-0023 — command palette and shortcuts; partially covers R40 (history navigation
  is not the same as a command palette, but both feed navigation).
- ADR-0016 — Prometheus integration; covers the data source for R30.
- ADR-0014 — port forwarding lifecycle; covers Network → Port Forwarding subtree.
- ADR-0017 — terminal sessions; covers the existence of PTY exec sessions but not the docked
  bottom-pane multi-tab terminal (R36) or node debug shell (R35).

### 4.2 Gherkin features already present

`docs/arch/contexts/app_shell/features/` contains:
`onboarding.feature` (welcome overlay first-launch, three-step tour, skip via Esc, empty cluster
state hint), `cluster-strip-pin-unpin.feature`, `tab-open-from-tree.feature`,
`tab-close-cancels-watches.feature`, `tab-persist-restore.feature`,
`detail-drawer-toolbar-actions.feature`, `resource-kind-catalog-discovery.feature`,
`command-palette.feature`, `keyboard-shortcuts.feature`, `diagnostics-export.feature`,
`window-lifecycle.feature`, `theme-and-typography.feature`, `icon-catalog.feature`,
`menu-bar-tray-overview.feature`, `menu-bar-tray-energy-and-lifecycle.feature`,
`menu-bar-tray-live-metrics.feature`, `loading-states.feature`,
`progressive-disclosure.feature`, `state-driven-realtime.feature`,
`toast-notifications.feature`, `markdown-viewer.feature`, `locale-selection.feature`,
`pluralization-and-formatting.feature`, `rtl-support.feature`, `accessibility.feature`,
`window-layout.feature`, `self-monitoring-diagnostics.feature`. Onboarding scenarios cover the
welcome overlay; they do not cover Welcome as a persistent tab (R2) nor the explicit
cluster-acquisition actions (R8 → R13).

### 4.3 Swift modules already in place

- `AppShell/Views/ClusterStrip/` — `ClusterStripView`, `ClusterAvatarButton`,
  `ClusterPickerSheet` (R1).
- `AppShell/Views/TabBar/TabBarView.swift` — multi-document tab strip (R2).
- `AppShell/Views/Chrome/` — `TopRightChrome`, `UserMenuButton`, `NotificationsButton`,
  `NotificationsPopover`, `AssistantToggleButton`, `AssistantSlideOutPanel` (R3, R38, R39).
- `AppShell/Views/Sidebar/` — `SidebarCanvasView`, `SidebarRowView`, `SidebarTreeView` (R6 left
  column, R16).
- `AppShell/Views/Detail/ResourceDetailDrawer.swift` plus `Detail/Sections/` (R29).
- `AppShell/Views/Resources/` subdivided into Cluster, Workloads, Config, Network, Storage,
  RBAC, CustomResources (R16, most categories implemented).
- `AppShell/Views/Editor/YAMLEditorTab.swift`, `ApplyConfirmationSheet.swift`,
  `DryRunPreviewPanel.swift`, `ValidationErrorPane.swift`, `YAMLEditorToolbar.swift` (R33
  partial — currently dispatched as a tab rather than a docked secondary pane).
- `AppShell/Views/ClusterOperations/ApplyYAMLView.swift` — YAML apply path (covers R10 if
  reused for clipboard kubeconfig, but no clipboard kubeconfig flow exists today).
- `AppShell/ViewModels/NodeDebugViewModel.swift` and `Views/Resources/Cluster/NodesListView.swift`
  reference node debug — confirms presence of the node debug shell concept (R35), pending
  bottom-docked terminal pane.
- `MetricsObservability/` adapters and `MetricsObservabilityView` exist (R30 data source), but
  no inline chart inside `ResourceDetailDrawer/Sections/` was found.
- `Views/Resources/Workloads/StatusBadge.swift` covers status pills for workloads. Equivalent
  badges for node `Conditions` (R26) are not yet documented.

## 5. Gap matrix

Each item is tagged PRESENT, PARTIAL or MISSING. PARTIAL means: a contract exists (ADR or
Gherkin) but no implementation, or implementation exists but does not match the reference
behaviour, or it exists in a different shape.

### 5.1 Chrome and workspace layout

- **R1** Vertical cluster strip — PRESENT (ADR-0051 + `ClusterStripView`).
- **R2** Persistent tab strip + Welcome tab — PARTIAL. Tab strip exists (`TabBarView`,
  ADR-0050). A Welcome tab as a dedicated `DocumentTab` kind is not specified. Onboarding
  overlay is modal, not a tab.
- **R3** Top-right chrome (assistant, bell, avatar) — PRESENT.
- **R4** Top-left history back/forward arrows — MISSING. No `HistoryStack` or navigation
  history actor; the existing back/forward is limited to the YAML editor breadcrumb. ADR draft
  required.
- **R5** Bottom status bar (cluster context + version + support link) — PARTIAL.
  `StatusBar/` directory exists; the support-link and `cluster (vX.Y.Z)` label format is
  unverified.
- **R6** Three-column navigator + list + detail drawer — PRESENT (ADR-0021, ADR-0051).
- **R7** Bottom-docked drag-resizable multi-tab terminal pane — MISSING. Terminal opens in a
  dedicated tab today (`TerminalSessionView`). Lens-style bottom split is undocumented.

### 5.2 Cluster acquisition and provider grouping

- **R8** Welcome screen with five start actions — MISSING (only the first-launch overlay exists,
  not a persistent Welcome tab with action buttons).
- **R9** First-launch onboarding wizard — PRESENT (Gherkin `onboarding.feature`).
- **R10** Add Kubeconfig from clipboard — MISSING (no Gherkin, no module).
- **R11** Add Kubeconfig from filesystem — PARTIAL. Kubeconfig loading exists
  (`cluster_connectivity/features/load-kubeconfig.feature`); explicit "from filesystem" entry
  point on the Welcome tab is not specified.
- **R12** AWS / EKS discovery — MISSING. `AWSExecCredentialAdapter` covers exec-credential
  flow but does not discover clusters from `aws eks list-clusters`.
- **R13** AKS discovery — MISSING. `AzureExecCredentialAdapter` covers exec credentials
  only.
- **R14** Provider grouping in the sidebar — PRESENT (ADR-0051,
  `Domain/ClusterStripPin.swift` enumerates AKS, EKS, GKE, OIDC, Local Kubeconfigs).
- **R15** Per-cluster status indicator — PRESENT in cluster strip, PARTIAL in sidebar tree (the
  sidebar tree row needs the dot too, per the recording).
- **R12a** GCP / GKE discovery — MISSING (companion to R12, R13).
- **R12b** DigitalOcean DOKS discovery — MISSING. The reference recording surfaces
  `do-nyc3-k8s-hood` and `do-nyc3-othersproject` as Local Kubeconfigs. Native discovery
  via `doctl kubernetes cluster list` would parallel the AWS/AKS flow but is out of scope
  unless an explicit ADR opts in.

### 5.3 Sidebar tree and resource taxonomy

- **R16** Per-cluster category tree — PRESENT (ADR-0050 + Sidebar views). Two gaps:
  - "Applications" (R16-a) — not defined; Lens uses this for Helm releases and applications;
    K8S-Manager surfaces Helm under Helm subtree. Decide whether to add an Applications root
    (Helm + ArgoCD Applications + Flux Kustomizations + bare-kubectl applied bundles) or
    leave Helm separate.
  - "Security Center" (R16-b) — `Views/Security/SecurityOverviewView`,
    `SecurityImagesView`, `SecurityResourcesView`, `SecurityRolesView` exist. Sidebar tree
    entry under per-cluster scope is not yet declared in ADR-0050.
- **R17** Custom Resources expanded subtree per API group — PRESENT (ADR-0052).
- **R18** Per-group kind drill-down — PRESENT (ADR-0052).
- **R19** TEAMWORK section — OUT OF SCOPE (proprietary Lens collaboration).

### 5.4 Resource list views

- **R20** Column-sortable virtualised list — PRESENT for the 51 standard kinds.
- **R21** Mini CPU / Memory / Disk bars per node row — MISSING. Node list shows columns but
  not live bars. Requires Prometheus query per row (or kubelet metrics fallback) with
  throttled refresh.
- **R22** Per-list namespace selector — PRESENT (ADR-0053).
- **R23** Per-list text search with case + regex toggles — PARTIAL. Most lists have search but
  case-sensitivity and regex toggles are not consistently exposed.
- **R24** Item count + CSV download — MISSING. Item count is sometimes present; CSV export of
  the visible list is undocumented and not implemented.
- **R25** Per-row 3-dot action menu — PARTIAL. Some lists expose context menus; the menu
  shape (edit YAML / delete / view events / copy link) is not uniform across all 51 kinds.
- **R26** Conditions chip in node rows — PARTIAL. Workloads have `StatusBadge`; an equivalent
  for nodes is needed.
- **R27** Resource counts in list pane bottom-right — PARTIAL (badge appears in some lists).
- **R28** Floating action button — MISSING. No FAB. Resource creation today flows through
  the YAML apply path or kind-specific create sheets.

### 5.5 Detail drawer

- **R29** Detail drawer with kind-specific action toolbar — PRESENT (ADR-0051,
  `ResourceDetailDrawer`).
- **R30** Node detail with embedded Prometheus chart — PARTIAL. `MetricsObservability` adapters
  exist; the chart is not yet embedded inside `Detail/Sections/`. ADR draft needed to specify
  the contract (which queries, time window, hover tooltip, no-Prometheus fallback).
- **R31** PersistentVolume detail sections — PARTIAL. Detail drawer can render a PV but the
  exact section list (Provider, Claim click-through, Driver introspection) is unverified.
- **R32** Secret detail with per-key reveal/hide toggle — PARTIAL. Secret list and view models
  exist; explicit reveal/hide affordance on a per-key basis and rendering of
  `kubernetes.io/dockerconfigjson` as parsed JSON is not documented.
- **R33** Inline docked YAML editor (secondary pane below the list) — PARTIAL. YAML editor
  exists as a tab; docked secondary-pane positioning is a new pattern.
- **R34** Save and apply path — PRESENT (ADR-0030, ADR-0012, `ApplyConfirmationSheet`).

### 5.6 Terminal and node debugging

- **R35** "Shell to Node" link from node detail header — PARTIAL. `NodeDebugViewModel` exists;
  the wiring from the detail drawer header to the bottom-docked terminal is missing.
- **R36** Bottom-docked multi-tab terminal pane — MISSING (see R7).
- **R37** Terminal connection state banner — PARTIAL. Terminal session reports state; the
  banner UI in a docked pane is undefined.

### 5.7 Assistant and notifications

- **R38** Prism AI assistant entry point — PRESENT (`AssistantToggleButton`,
  `AssistantSlideOutPanel`).
- **R39** Notifications bell with badge — PRESENT (`NotificationsButton`,
  `NotificationsPopover`).

### 5.8 Navigation primitives

- **R40** History back / forward — MISSING (see R4).
- **R41** Home / workspace scope selector — OUT OF SCOPE.

## 6. Proposed new ADRs

The following ADRs are required to close the gaps. Each is listed with its motivation, the
reference items it satisfies, and the contexts it touches.

- **ADR-0054 — Welcome tab and cluster-acquisition entry surface** — defines a persistent
  Welcome `DocumentTab` (kind `welcome`) that hosts five canonical start actions: paste
  kubeconfig, import kubeconfig file, discover AWS clusters, discover AKS clusters, discover
  GKE clusters. Splits from the modal first-launch overlay (which remains as defined in
  `onboarding.feature`). Satisfies R2, R8. Contexts: app_shell, cluster_connectivity.
- **ADR-0055 — Cloud provider cluster discovery (AWS, Azure, GCP)** — defines provider-side
  port contracts to enumerate clusters from AWS (`eks:ListClusters` + `eks:DescribeCluster`),
  Azure (`Microsoft.ContainerService/managedClusters`), GCP
  (`container.googleapis.com/v1/projects/*/locations/*/clusters`), and the kubeconfig
  materialisation rules (exec block selection per provider matches existing
  `AWSExecCredentialAdapter`, `AzureExecCredentialAdapter`, `GCPExecCredentialAdapter`).
  Satisfies R12, R13, R12a. Contexts: cluster_connectivity, app_shell.
- **ADR-0056 — Kubeconfig import from clipboard** — defines the paste-YAML flow: parse,
  validate via `YamsKubeconfigAdapter`, surface validation errors in a sheet, on accept call
  the existing `cluster_connectivity` import path. Satisfies R10. Contexts:
  cluster_connectivity, app_shell.
- **ADR-0057 — Bottom-docked terminal pane with node-debug shell integration** — defines a
  resizable bottom split below the list pane (separate from `TerminalSessionView` tab) that
  hosts multi-tab PTY sessions, fullscreen toggle, search-in-output, and a "Shell to Node"
  entry point from the node detail drawer header. The node debug shell launches via
  `kubectl debug node` semantics already designed in `NodeDebugViewModel`. Satisfies R7,
  R35, R36, R37. Contexts: app_shell, terminal_session, resource_browser.
- **ADR-0058 — Embedded Prometheus charts in resource detail drawer** — defines a reusable
  `MetricSparkline` and `MetricChart` section that the detail drawer composes for Nodes,
  Pods, Deployments, StatefulSets, DaemonSets. Defines the default time range, queries,
  redraw cadence, and the no-Prometheus fallback. Satisfies R30, partial R31. Contexts:
  metrics_observability, app_shell.
- **ADR-0059 — Resource list mini-bars (Node CPU / Memory / Disk per row)** — defines the
  inline per-row sparkbar contract: throttled refresh, Prometheus query per node, kubelet
  fallback, colour scheme, capacity-relative rendering. Satisfies R21. Contexts:
  metrics_observability, resource_browser, app_shell.
- **ADR-0060 — Resource list export (CSV and YAML)** — defines per-list download action that
  exports the visible (filtered, sorted) list as CSV with a fixed column subset, plus per-row
  YAML download from the 3-dot menu. Satisfies R24. Contexts: resource_browser, app_shell.
- **ADR-0061 — Per-row resource action menu uniform shape** — defines the canonical action
  menu items per kind family (Workloads, Config, Network, Storage, RBAC, Custom Resources)
  so every list exposes the same shape (edit YAML, delete with double-confirm, view events,
  copy resource link, view in tab). Satisfies R25. Contexts: resource_browser, app_shell.
- **ADR-0062 — Status chips and node conditions presentation** — defines the chip palette
  (`Ready`, `NotReady`, `SchedulingDisabled`, `MemoryPressure`, `DiskPressure`, `PIDPressure`,
  `NetworkUnavailable`) and the row vs detail-drawer rendering rules. Satisfies R26.
  Contexts: resource_browser, app_shell.
- **ADR-0063 — Secret data presentation (reveal, hide, dockerconfigjson parser)** — defines
  the per-key reveal/hide toggle, the audit log entry on reveal, the copy-to-clipboard rule
  (always with a toast confirmation), and the docker-config JSON parser that renders
  `auths`, `username`, `password` rows. Satisfies R32. Contexts: resource_browser,
  app_shell.
- **ADR-0064 — Inline docked YAML editor pane** — extends ADR-0030 by adding a docked
  secondary pane positioning under the list pane (rather than a dedicated tab) for quick
  edits without losing list context. Defines the layout host, dismissal rules, and
  unsaved-changes guard. Satisfies R33. Contexts: app_shell.
- **ADR-0065 — Navigation history stack** — defines a per-window back/forward history of
  resource selections (cluster + kind + namespace + selected name + drawer state). Hooks
  into `OpenTabsActor` and the detail drawer. Satisfies R4, R40. Contexts: app_shell.
- **ADR-0066 — Floating action button for resource creation** — defines a FAB at the
  bottom-right of the list pane that opens a kind-aware create flow (apply YAML from
  scratch, paste-from-clipboard, fork-from-existing). Satisfies R28. Contexts:
  resource_browser, app_shell.
- **ADR-0067 — Applications cluster scope (Helm releases plus GitOps applications)** —
  decides whether to introduce an Applications root in the sidebar that aggregates Helm
  releases, ArgoCD Applications, and Flux Kustomizations, or to keep Helm and GitOps tools
  as separate subtrees. Satisfies R16-a. Contexts: helm_management, resource_browser.
- **ADR-0068 — Security Center sidebar surface and content** — declares the Security Center
  entry under the per-cluster tree and pins which views compose it
  (`SecurityOverviewView`, `SecurityImagesView`, `SecurityResourcesView`,
  `SecurityRolesView`). Satisfies R16-b. Contexts: resource_browser, app_shell.

## 7. Proposed new Gherkin features

For each new ADR, at least one Gherkin file under
`docs/arch/contexts/<ctx>/features/` is required. The minimum set:

- `app_shell/features/welcome-tab.feature` — five start actions visible, Welcome tab is
  never auto-closed, reopens via command palette.
- `cluster_connectivity/features/kubeconfig-paste-from-clipboard.feature` — paste-validate-
  accept; reject on invalid YAML with a sheet error.
- `cluster_connectivity/features/aws-cluster-discovery.feature` — enumerate, select,
  import; reject on missing credentials with a clear message.
- `cluster_connectivity/features/azure-cluster-discovery.feature` — same shape.
- `cluster_connectivity/features/gcp-cluster-discovery.feature` — same shape.
- `app_shell/features/bottom-docked-terminal-pane.feature` — open from node detail, resize,
  multi-tab, fullscreen, close.
- `metrics_observability/features/detail-drawer-metric-chart.feature` — chart visible when
  Prometheus is configured; fallback message when not.
- `resource_browser/features/node-row-live-mini-bars.feature` — bars update on Prometheus
  push; freeze on cluster disconnect.
- `resource_browser/features/list-export-csv.feature` — export visible filtered list.
- `resource_browser/features/row-action-menu-uniform.feature` — canonical menu items per
  family.
- `resource_browser/features/secret-key-reveal-hide.feature` — per-key reveal, audit log,
  clipboard copy.
- `app_shell/features/inline-docked-yaml-editor.feature` — docked pane open, edit, save,
  cancel, unsaved-changes guard.
- `app_shell/features/navigation-history-back-forward.feature` — per-window back/forward
  across tabs and drawer states.
- `resource_browser/features/list-floating-action-button.feature` — FAB visible per list,
  opens create flow.
- `resource_browser/features/applications-scope.feature` — once ADR-0067 chooses an option.
- `app_shell/features/security-center-tree-entry.feature` — Security Center entry order,
  empty state.

## 8. Priority and risk

The recording is dense and surfaces a wide surface. Suggested priority bands (final order
deferred to product planning):

- Band A (closes the Lens parity claim and unblocks new operators): R4, R7, R8, R10, R11,
  R15, R21, R30, R32, R35, R36 (Welcome tab, clipboard paste, kubeconfig import surface,
  bottom-docked terminal pane, node debug shell integration, embedded metric chart,
  per-row mini bars, secret reveal, navigation history). Estimated 9–11 ADRs.
- Band B (presentation polish): R23, R24, R25, R26, R27, R28, R33 (search toggles, CSV
  export, row action menu uniformity, status chips, FAB, inline docked editor).
- Band C (cloud-provider depth): R12, R13, R12a (cluster discovery flows). Each
  provider integration carries auth scope risk and is best advanced behind a Gherkin
  scenario covering "user is not authenticated" before any positive scenario.
- Band D (decisions): R16-a (Applications scope), R16-b (Security Center taxonomy).

Risks:

- The bottom-docked terminal pane (R7) interacts with the existing `TerminalSessionView`
  tab. ADR-0057 must decide whether the tab survives as a long-running session view or is
  collapsed into the docked pane.
- The metric chart embedded in the detail drawer (R30) doubles the Prometheus query load
  per cluster. ADR-0058 must include a refresh-cadence ceiling.
- Cluster discovery flows (R12, R13) require careful credential boundary handling — the
  app must never request broader AWS/Azure/GCP scopes than needed.
- The TEAMWORK section is explicitly out of scope. Care should be taken so that future
  product asks do not pull collaboration features in without a fresh decision.

## 9. Followups inside this document

- Confirm whether the recording's status bar shows the cluster name or the cluster context
  identifier (looks like display name) — affects ADR-0051 status-bar copy.
- Re-watch the recording with audio (if any) to confirm provider names where the recording
  resolution made them ambiguous (`do-nyc3-k8s-hood`, `do-nyc3-othersproject` are
  DigitalOcean; the AKS and EKS group labels are unambiguous).
- Inspect Lens documentation to confirm that the FAB (R28) opens an apply-YAML sheet or
  a kind-aware create flow — the recording shows only the FAB shape, not the action.

## 10. References

- ADR-0021 — `docs/arch/decisions/adr-0021-app-shell-design-system-and-layout.md`
- ADR-0030 — `docs/arch/decisions/adr-0030-integrated-editor-md-yaml-json.md`
- ADR-0050 — `docs/arch/decisions/adr-0050-resource-navigation-taxonomy.md`
- ADR-0051 — `docs/arch/decisions/adr-0051-multi-cluster-workspace.md`
- ADR-0052 — `docs/arch/decisions/adr-0052-custom-resource-discovery-and-rendering.md`
- ADR-0053 — `docs/arch/decisions/adr-0053-global-namespace-filter-and-selection-propagation.md`
- Onboarding feature — `docs/arch/contexts/app_shell/features/onboarding.feature`
- Source recording — `~/Movies/Screen Recording 2026-05-16 at 13.19.58.mov`
