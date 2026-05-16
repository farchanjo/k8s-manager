workspace "K8sManager" "macOS-native Kubernetes manager with built-in LLM assistant, in-process MCP server, native cloud auth, 100% REST-API integration (no kubectl/helm/aws/gcloud/kubelogin subprocess), per-cluster isolated HTTPClient pools backed by kqueue I/O event selection (EVFILT_READ/WRITE/VNODE/TIMER/SIGNAL/PROC), reactive stack end-to-end (kqueue → AsyncSequence → actor → @Observable → SwiftUI, ADR-0035), integrated MD/YAML/JSON editor with dry-run apply and diff preview (ADR-0030), i18n via Xcode String Catalog (ADR-0033), state-driven UI via Observation framework (ADR-0034), session restoration across launches, ~/.config/k8smanager/ filesystem layout, and SF Symbols iconography — MVP++ per ADR-0006, ADR-0012, ADR-0018, ADR-0025, ADR-0026, ADR-0028, ADR-0029." {

    model {
        operator = person "Kubernetes Operator" "Workstation user managing one or more Kubernetes clusters and interacting with the in-app assistant."

        k8sManager = softwareSystem "K8sManager" "macOS-native Kubernetes manager." {

            // Bounded-context containers (domain cores)
            appShell = container "App Shell" "SwiftUI window with Lens IDE-style chrome: vertical cluster strip (ClusterStripActor) + per-cluster sidebar tree (provider-grouped, 8 resource categories per ADR-0050; Applications root per ADR-0067; Security Center per ADR-0068) + multi-document tab bar (OpenTabsActor, persistent tabs per cluster, tab-owned watch streams per ADR-0050/0036; persistent Welcome tab kind per ADR-0054; applicationsList tab kind per ADR-0067) + detail drawer (metrics chart MetricChart/MetricSparkline per ADR-0058 + StatusChip per ADR-0062 + Shell-to-Node action per ADR-0057 + Edit YAML row action opening DockedEditorPaneOrchestrator per ADR-0064 + properties + events + action toolbar per ADR-0051) + bottom-docked terminal pane (DockedTerminalPane actor per ADR-0057) coexists with inline docked YAML editor pane (mutually exclusive per ADR-0064) + status bar (cluster telemetry) + top-right chrome (assistant toggle, notifications, user menu) + top-left history back/forward arrows backed by NavigationHistoryActor per ADR-0065; command palette ⌘P/⌘K; keyboard shortcuts (Welcome tab ⌘⇧W, diff overlay ⌘⇧D, FAB ⌘N); FAB (Floating Action Button) per resource list pane with three-path popover (create-from-scratch / paste-from-clipboard / fork-from-selected) per ADR-0066; per-row 3-dot action menu via RowActionMenuBuilder per ADR-0061; SF Symbols + custom symbol set; app self-monitoring (ADR-0027); state restoration on launch (ADR-0026); toast notifications (ADR-0032); loading skeletons / shimmer / spinner (ADR-0031); i18n catalog — en / pt-BR / es-ES baseline (ADR-0033); state-driven UI via @Observable + AsyncSequence (ADR-0034)." "Swift / SwiftUI"
            tabSessionManager = container "TabSessionManager" "Application-scope actor pair managing the multi-document tab bar and cluster strip. OpenTabsActor owns DocumentTab ordered list, watcher-task registry, tab persistence (open-tabs.json per cluster, debounced 500 ms), and AsyncStream<[DocumentTab]> for the tab bar view model. ClusterStripActor owns ClusterStripPin ordered list, strip persistence (workspace/cluster-strip-pins.json), and AsyncStream<[ClusterStripPin]> for the strip view. Enforces tab invariants: max 20 tabs/cluster, identity-tuple dedup, cross-cluster isolation, LRU eviction signalling to ClusterSessionActor. Defined in ADR-0050 and ADR-0051." "Swift / actor"
            contextNavigation = container "Context Navigation" "Active context, recents, pinned items." "Swift"
            clusterConnectivity = container "Cluster Connectivity" "Parses kubeconfig, probes cluster health, owns KubernetesApiPort, ExecCredentialPort, CloudClusterDiscoveryPort (ADR-0055 — AWS/Azure/GCP cluster discovery adapters reusing ADR-0018 credential chain), KubeconfigClipboardImportPort (ADR-0056 — paste-from-clipboard validate-then-import flow via YamsKubeconfigAdapter), and a ClusterSessionActor per cluster with isolated HTTPClient pool, dedicated MultiThreadedEventLoopGroup (kqueue underneath), credential cache, and watch/exec/portforward/terminal registries (ADR-0025)." "Swift"
            clusterIntelligence = container "Cluster Intelligence" "In-process MCP server (read-only K8s tool registry + Rego policy gate)." "Swift / MCP"
            assistantChat = container "Assistant Chat" "Chat sessions, tool-use loop, MCP host." "Swift"
            llmProvider = container "LLM Provider" "Provider port abstracting Anthropic, OpenAI, OpenAI-compatible endpoints." "Swift"
            localPersistence = container "Local Persistence" "SQLite (WAL) at ~/.config/k8smanager/storage.sqlite3 for non-secret state; macOS Keychain for LLM API keys; per-cluster JSON view-state files; logs and exports under ~/.config/k8smanager/ (ADR-0026)." "Swift / GRDB / Security"
            resourceBrowser = container "Resource Browser" "Full CRUD with confirmation, double-confirm delete, audit log, server-side apply; integrated MD/YAML/JSON editor with realtime dry-run apply, diff preview, and Kubernetes schema validation (ADR-0030); inline docked YAML editor pane orchestrator (ADR-0064); ApplicationsView read-model projection of Helm releases (ADR-0067, Option C — Helm-only v1); Security Center read-models (Overview / Images / Resources / Roles per ADR-0068); SecretDataRevealViewModel with per-key reveal, dockerconfigjson and TLS parsers, 60-second auto-hide, 90-second clipboard clear, HMAC-chained audit entries in secret_reveal_audit (ADR-0063); ListExportService (CSV + per-row YAML export with Secret redaction policy per ADR-0060); RowActionMenuBuilder (per-family canonical row action menu, ADR-0061); FabVisibilityPolicy + KindSkeletonTemplate registry (ADR-0066); StatusChip variant mapping with node-condition semantic resolver (ADR-0062); MetricMiniBar viewport-gated row metric strips (ADR-0059)." "Swift"
            portForwarding = container "Port Forwarding" "Local TCP listener tunnels via WebSocket portforward.k8s.io subprotocol." "Swift"
            helmManagement = container "Helm Management" "Native Helm release list/inspect/history/rollback over Secrets type helm.sh/release.v1 (Phase 1); install/upgrade/template/lint native engine (Phase 2 roadmap)." "Swift"
            metricsObservability = container "Metrics Observability" "Prometheus HTTP API client with auto-discovery and curated PromQL templates (extended in ADR-0058 with Node/Pod/Workload drawer four-series sets and in ADR-0059 with resource-list mini-bar batch query templates); MetricChart and MetricSparkline SwiftUI contracts consumed by ResourceDetailDrawer (ADR-0058); per-(endpointId, queryId) 15-second refresh ceiling enforced by MetricsObservabilityActor; ADR-0044 PromQL injection guard via curated_template_keys policy allowlist." "Swift"
            terminalSession = container "Terminal Session" "Pod exec and Node debug sessions via WebSocket v5.channel.k8s.io subprotocol, multi-tab. DockedTerminalPane (ADR-0057) hosts ad-hoc sessions opened from resource detail drawers (Shell-to-Node action) alongside the dedicated TerminalSessionView tab for long-running sessions; both share the TerminalSessionActor transport. Pane chrome: drag-resize handle, fullscreen toggle, per-tab connection-state banner, search-in-output, workspace-scoped persistence to docked-terminal-pane.json. Mutually exclusive with the inline docked YAML editor pane (ADR-0064)." "Swift"

            // Infrastructure adapters
            swiftkubeAdapter = container "SwiftkubeClient Adapter" "swiftkube/client + async-http-client; per-cluster isolated HTTPClient instances with dedicated MultiThreadedEventLoopGroup (kqueue I/O selector — ADR-0029); PATCH server-side apply custom route." "Swift / SwiftkubeClient / SwiftNIO"
            yamsAdapter = container "Yams Kubeconfig Adapter" "Parses kubeconfig YAML (read-only)." "Swift / Yams"
            grdbAdapter = container "GRDB Persistence Adapter" "WAL SQLite store via GRDB.swift v7+." "Swift / GRDB"
            keychainAdapter = container "Keychain Adapter" "macOS Keychain (kSecClassGenericPassword) for LLM API keys." "Security framework"
            wsExecAdapter = container "WebSocket Exec Adapter" "URLSessionWebSocketTask + v5.channel.k8s.io channel framing." "Swift / Foundation"
            wsPortForwardAdapter = container "WebSocket PortForward Adapter" "URLSessionWebSocketTask + portforward.k8s.io subprotocol." "Swift / Foundation"
            mcpAdapter = container "MCP SDK Adapter" "modelcontextprotocol/swift-sdk with InMemoryTransport." "Swift / MCP SDK"
            anthropicAdapter = container "Anthropic Adapter" "SwiftAnthropic 2.2.x — Messages API streaming SSE + prompt caching." "Swift"
            openaiAdapter = container "OpenAI Adapter" "MacPaw/OpenAI 0.4.x — Chat Completions / Responses API + tool_calls." "Swift"
            openaiCompatibleAdapter = container "OpenAI-Compatible Adapter" "MacPaw/OpenAI with baseURL override for Ollama, LM Studio, vLLM, OpenRouter." "Swift"
            awsAuthAdapter = container "AWS Exec Credential Adapter" "soto-project/soto SigV4 + STS GetCallerIdentity presign + k8s-aws-v1 token assembly." "Swift / soto"
            gcpAuthAdapter = container "GCP Exec Credential Adapter" "ADC + service account JWT (vapor/jwt-kit RS256) + Workload Identity Federation." "Swift / jwt-kit / URLSession"
            azureAuthAdapter = container "Azure Exec Credential Adapter" "MSAL device flow + service principal; manual IMDS for Managed Identity." "Swift / MSAL"
            oidcAuthAdapter = container "OIDC Exec Credential Adapter" "AppAuth-iOS AuthCode+PKCE + refresh + JWKS validation." "Swift / AppAuth"
            subprocessAuthAdapter = container "Subprocess Exec Adapter (fallback)" "Spawns custom exec plugin binaries when no native adapter matches (ADR-0002 compatibility)." "Swift / Foundation.Process"
            prometheusAdapter = container "Prometheus Query Adapter" "Custom HTTP client over URLSession.bytes; matrix/vector/scalar/string result decoder (~340 LoC, no public Swift lib exists)." "Swift / URLSession"
            sqliteStore = container "SQLite Storage" "WAL-mode SQLite database for chat history, profiles, cache, log, prefs, audit." "SQLite 3"
            preferencesAdapter = container "Preferences Adapter" "UserDefaults overlay for transient UI state (window frame)." "Swift / UserDefaults"
            menuBarTray = container "Menu Bar Tray" "NSStatusItem with live cluster status widget, live metrics sparklines (CPU/mem/network/pods), recent mutations, active sessions, cluster picker. Refresh interval 5-60s; pauses on lid close, low power, or network unreachable." "Swift / SwiftUI / NSStatusItem"
            analyticsDashboard = container "Analytics Dashboard" "Multi-scope analytics dashboards (cluster / namespace / pod / node / workload / service / Helm release / debug timeline / topology). Widgets: sparklines, line charts, heatmaps p50/p95/p99, stacked bars, counts, top lists, event timelines, topology graphs, log error rates, diff viewers, conditions lists. Drill-down via click. Auto-refresh 5-60s." "Swift"

            // Cross-context event bus (publish/subscribe abstraction, not a service)
            // Defined per ADR-0040. Producers publish typed EventEnvelope values;
            // consumers receive an AsyncStream<EventEnvelope> per subscription.
            // bufferingOldest(64) per subscriber (ADR-0035). No replay; at-most-once delivery.
            domainEventBus = container "DomainEventBusActor" "In-process typed event bus implementing DomainEventBusPort (ADR-0040). Maintains per-subscriber AsyncStream<EventEnvelope> continuations keyed by sourceContext and subscriberId. Emits DomainEventDropped to a dedicated meta-stream on buffer overflow. Producers never suspend; cancellation propagates through Swift structured concurrency Task trees." "Swift / AsyncStream"
        }

        // External systems
        kubeconfigFile = softwareSystem "Kubeconfig File" "User-managed YAML at KUBECONFIG or ~/.kube/config." "External"
        kubernetesApi = softwareSystem "Kubernetes API Server" "Remote cluster API endpoint (multi-cluster). 1.31+ for WebSocket exec and portforward." "External"
        anthropicApi = softwareSystem "Anthropic Messages API" "Anthropic-hosted LLM endpoint with SSE streaming and tool_use blocks." "External"
        openaiApi = softwareSystem "OpenAI API" "OpenAI-hosted Chat Completions / Responses endpoints." "External"
        openaiCompatible = softwareSystem "OpenAI-Compatible Endpoint" "Local or hosted server speaking the OpenAI API surface (Ollama, LM Studio, vLLM, OpenRouter)." "External"
        awsSts = softwareSystem "AWS STS" "AWS Security Token Service for GetCallerIdentity presign and AssumeRole(WithWebIdentity)." "External"
        gcpOauth = softwareSystem "Google OAuth and STS" "OAuth2 token endpoint and Workload Identity Federation STS endpoint." "External"
        azureAd = softwareSystem "Microsoft Entra ID / Azure AD" "OAuth2 endpoints for device flow, service principal, Managed Identity, Workload Identity Federation." "External"
        oidcProvider = softwareSystem "OIDC Identity Provider" "Generic OIDC issuer (Keycloak, Auth0, Okta, custom) with discovery and JWKS." "External"
        prometheusServer = softwareSystem "Prometheus Server" "In-cluster Prometheus (kube-prometheus-stack typical) exposing /api/v1/query, /api/v1/query_range, /api/v1/series." "External"
        execPlugin = softwareSystem "Custom Exec Credential Plugin" "External binary printing an ExecCredential JSON for kubeconfig exec blocks without a native adapter." "External"

        // Operator interactions
        operator -> appShell "Switches contexts, browses resources, edits YAML, opens terminals, configures providers, chats with assistant, watches metrics"
        operator -> analyticsDashboard "Selects scope; clicks widgets to drill down"

        // TabSessionManager relationships (ADR-0050, ADR-0051)
        tabSessionManager -> clusterConnectivity "OpenTabsActor issues WatchPort.watch/GVRWatchPort.watch per tab open; cancels via Task.cancel per tab close; reads ClusterSessionActor watch budget"
        tabSessionManager -> localPersistence "Persists open-tabs.json per cluster and workspace/cluster-strip-pins.json via atomic write; reads both on cold launch"
        tabSessionManager -> domainEventBus "Publishes TabOpened, TabClosed, TabFocused, ClusterStripPinned, ClusterStripUnpinned, ClusterStripReordered; subscribes to ClusterSessionClosed to cascade tab teardown"
        appShell -> tabSessionManager "Reads AsyncStream<[DocumentTab]> for tab bar rendering; reads AsyncStream<[ClusterStripPin]> for cluster strip rendering; issues openTab/closeTab/focusTab/pinCluster commands"

        // App Shell consumes read models
        appShell -> analyticsDashboard "Reads DashboardCatalogReadModel for the sidebar dashboards section"
        appShell -> contextNavigation "Reads ActiveContext, SidebarReadModel"
        appShell -> clusterConnectivity "Reads ClusterReadModel and KubeconfigLoadReportReadModel"
        appShell -> assistantChat "Reads OpenSessionsReadModel and LiveTurnReadModel"
        appShell -> llmProvider "Reads ProviderListReadModel via settings"
        appShell -> resourceBrowser "Reads ResourceListReadModel, ResourceDetailReadModel, MutationAuditReadModel"
        appShell -> portForwarding "Reads ActivePortForwardsReadModel"
        appShell -> helmManagement "Reads ReleaseListReadModel, ReleaseDetailReadModel"
        appShell -> metricsObservability "Reads PrometheusEndpointStatusReadModel, CuratedQueryCatalogReadModel"
        appShell -> terminalSession "Reads OpenTerminalsReadModel"
        appShell -> localPersistence "Reads operator preferences via OperatorPreferencesPort"

        // Context navigation
        contextNavigation -> clusterConnectivity "Reads ClusterReadModel"
        contextNavigation -> localPersistence "Persists pins and recents"

        // Cluster connectivity is the central hub of K8s I/O
        clusterConnectivity -> yamsAdapter "Loads kubeconfig (read-only); parses pasted YAML for clipboard import (ADR-0056)"
        clusterConnectivity -> swiftkubeAdapter "Probes /readyz via pooled HTTPClient"
        clusterConnectivity -> awsAuthAdapter "Resolves credentials via ExecCredentialPort for EKS-style kubeconfig entries; AWSClusterDiscoveryAdapter enumerates clusters via eks:ListClusters + eks:DescribeCluster (ADR-0055)"
        clusterConnectivity -> gcpAuthAdapter "Resolves credentials for GKE-style entries; GCPClusterDiscoveryAdapter enumerates clusters via container.googleapis.com/v1/projects/*/locations/*/clusters (ADR-0055)"
        clusterConnectivity -> azureAuthAdapter "Resolves credentials for AKS-style entries; AzureClusterDiscoveryAdapter enumerates clusters via Microsoft.ContainerService/managedClusters ARM endpoint (ADR-0055)"
        clusterConnectivity -> oidcAuthAdapter "Resolves credentials for OIDC exec blocks"
        clusterConnectivity -> subprocessAuthAdapter "Fallback for unknown exec plugins (compat with ADR-0002)"
        yamsAdapter -> kubeconfigFile "Reads YAML"
        swiftkubeAdapter -> kubernetesApi "HTTPS over pooled connections (ADR-0007)"
        awsAuthAdapter -> awsSts "POST /v1/STS GetCallerIdentity (presigned URL)"
        gcpAuthAdapter -> gcpOauth "POST /token + STS token exchange"
        azureAuthAdapter -> azureAd "OAuth2 device flow / service principal / Managed Identity"
        oidcAuthAdapter -> oidcProvider "Authorization Code + PKCE + JWKS"
        subprocessAuthAdapter -> execPlugin "Spawns and parses ExecCredential JSON"

        // Cluster intelligence (MCP server)
        clusterIntelligence -> clusterConnectivity "Reads ClusterReadModel, uses KubernetesApiPort"
        clusterIntelligence -> swiftkubeAdapter "Issues read-only verbs after policy gate"
        clusterIntelligence -> localPersistence "Persists MCP invocation log"

        // Resource browser (mutating ops)
        resourceBrowser -> clusterConnectivity "Reads ClusterReadModel"
        resourceBrowser -> swiftkubeAdapter "List, get, watch via KubernetesApiPort; PATCH server-side apply via custom adapter route"
        resourceBrowser -> localPersistence "Persists cluster_mutation_audit entries (ADR-0012, ADR-0047) and secret_reveal_audit entries (ADR-0063 — per-key Secret reveal / clipboard-copy / auto-hide events; HMAC-chained, decoded values never stored)"
        resourceBrowser -> helmManagement "Reads HelmManagement read model for ApplicationsView (ADR-0067 Option C); row action navigates to helmDetail DocumentTab"
        resourceBrowser -> metricsObservability "Issues batched PromQL queries via curated_template_keys allowlist for Node/Pod list mini-bars (ADR-0059) and drawer charts (ADR-0058)"
        resourceBrowser -> terminalSession "Shell-to-Node header action on the Node detail drawer opens a DockedTerminalTab via NodeDebugViewModel (ADR-0057)"

        // Port forwarding
        portForwarding -> clusterConnectivity "Reads ClusterReadModel"
        portForwarding -> wsPortForwardAdapter "Opens portforward.k8s.io WebSocket"
        wsPortForwardAdapter -> kubernetesApi "WebSocket upgrade to /api/v1/namespaces/.../pods/.../portforward"

        // Helm management
        helmManagement -> swiftkubeAdapter "Lists Secrets owner=helm; reads release blob"
        helmManagement -> clusterConnectivity "Submits rollback apply via ServerSideApplyPort (owned by cluster_connectivity); no dependency on resource_browser"
        helmManagement -> localPersistence "Caches release decode result for navigation speed"

        // Metrics observability
        metricsObservability -> clusterConnectivity "Discovers Prometheus Service in cluster"
        metricsObservability -> prometheusAdapter "Issues PromQL via /api/v1/query, /api/v1/query_range"
        metricsObservability -> localPersistence "Persists endpoint overrides"
        prometheusAdapter -> prometheusServer "HTTPS query and query_range"

        // Terminal session
        terminalSession -> swiftkubeAdapter "Creates ephemeral debug pod when kind=node_debug"
        terminalSession -> wsExecAdapter "Opens pods/exec WebSocket"
        wsExecAdapter -> kubernetesApi "WebSocket upgrade with subprotocol v5.channel.k8s.io"

        // Assistant chat
        assistantChat -> llmProvider "Streams replies via LLMProviderPort"
        assistantChat -> clusterIntelligence "Executes tool calls via MCP protocol (in-process transport)"
        assistantChat -> contextNavigation "Reads pinned ContextId for the session"
        assistantChat -> localPersistence "Persists sessions, messages, tool-call records"
        assistantChat -> mcpAdapter "Hosts MCP client side of in-process transport"

        // LLM providers
        llmProvider -> anthropicAdapter "Streams via SwiftAnthropic"
        llmProvider -> openaiAdapter "Streams via MacPaw/OpenAI (api.openai.com)"
        llmProvider -> openaiCompatibleAdapter "Streams via MacPaw/OpenAI with baseURL override"
        llmProvider -> localPersistence "Reads ProviderProfile rows; resolves API key from Keychain via LLMKeyStorePort"
        anthropicAdapter -> anthropicApi "POST /v1/messages with SSE streaming"
        openaiAdapter -> openaiApi "POST chat completions / responses with SSE streaming"
        openaiCompatibleAdapter -> openaiCompatible "POST OpenAI-compatible endpoints"

        // Persistence
        localPersistence -> grdbAdapter "Writes/reads via GRDB.swift v7+"
        localPersistence -> keychainAdapter "Stores LLM API keys"
        grdbAdapter -> sqliteStore "Embedded SQLite with WAL"

        // App shell preferences
        appShell -> preferencesAdapter "Transient UI prefs (window frame)"

        // -----------------------------------------------------------------------
        // DomainEventBus fan-out (ADR-0040 — publish/subscribe; arrows show direction of event flow)
        // Producers publish to the bus; the bus fans out to subscribers.
        // Each arrow is directional: publisher -> bus for publish; bus -> subscriber for subscribe.
        // -----------------------------------------------------------------------

        // Producers -> DomainEventBus
        resourceBrowser -> domainEventBus "publish MutationApplied, MutationFailed, DraftSaved, DraftPruned"
        clusterConnectivity -> domainEventBus "publish ClusterSessionOpened, ClusterSessionClosed, ClusterSessionDegraded, WatchStreamReconnected, WatchStreamDropped"
        portForwarding -> domainEventBus "publish PortForwardEstablished, PortForwardClosed"
        terminalSession -> domainEventBus "publish TerminalSessionOpened, TerminalSessionClosed"
        helmManagement -> domainEventBus "publish HelmRollbackInitiated, HelmRollbackCompleted"
        clusterIntelligence -> domainEventBus "publish ToolInvoked"
        localPersistence -> domainEventBus "publish AuditEntryAppended"
        appShell -> domainEventBus "publish LocaleChanged, ThemeChanged, PreferencesUpdated, ContextSwitched, DiagnosticsCollected"

        // DomainEventBus -> Subscribers (AsyncStream<EventEnvelope> per subscriber)
        domainEventBus -> analyticsDashboard "subscribe ClusterSession*, MutationApplied, WatchStream*, PortForward*, HelmRollback*, ToolInvoked, AuditEntryAppended, DraftSaved"
        domainEventBus -> appShell "subscribe ClusterSession*, MutationApplied, DraftSaved, PortForward*"
        domainEventBus -> localPersistence "subscribe MutationApplied (projects to mutation_audit); AuditEntryAppended (projects to audit_log)"
        domainEventBus -> clusterIntelligence "subscribe ClusterSessionOpened, ClusterSessionClosed, MutationApplied"
        domainEventBus -> contextNavigation "subscribe ClusterSessionOpened, ClusterSessionClosed, ContextSwitched"
        domainEventBus -> assistantChat "subscribe ToolInvoked"
        domainEventBus -> resourceBrowser "subscribe WatchStreamReconnected, DraftSaved"
        domainEventBus -> portForwarding "subscribe ClusterSessionClosed (cascade teardown)"
        domainEventBus -> terminalSession "subscribe MutationApplied (wait for debug Pod ready)"

        // Analytics dashboard
        analyticsDashboard -> clusterConnectivity "Reads ClusterReadModel and KubernetesApiPort for kube-state aggregations"
        analyticsDashboard -> resourceBrowser "Reads ResourceListReadModel and MutationAuditReadModel for resource counts and audit timeline"
        analyticsDashboard -> metricsObservability "Issues PromQL via prometheusAdapter for sparklines, heatmaps, counts, log error rate"
        analyticsDashboard -> helmManagement "Reads ReleaseListReadModel and ReleaseDetailReadModel for HelmReleaseDetail scope and topology"
        analyticsDashboard -> clusterIntelligence "Reads MCPInvocationLogReadModel for debug timeline assistant tool calls"
        analyticsDashboard -> localPersistence "Persists dashboard customisation via DashboardPreferencesPort"
        analyticsDashboard -> menuBarTray "Reuses widget catalog from tray_metric_widget.cue for shared widgets"

        // Menu bar tray
        menuBarTray -> contextNavigation "Reads ActiveContext, switches active context via header dropdown"
        menuBarTray -> clusterConnectivity "Reads ClusterReadModel for health badge"
        menuBarTray -> metricsObservability "Issues PromQL queries for sparklines via prometheusAdapter"
        menuBarTray -> resourceBrowser "Reads MutationAuditReadModel for recent mutations widget"
        menuBarTray -> portForwarding "Reads ActivePortForwardsReadModel for sessions count"
        menuBarTray -> terminalSession "Reads OpenTerminalsReadModel for sessions count"
        appShell -> menuBarTray "Owns lifecycle and observes TrayCommand notifications via TrayCommandPort (open main window, open chat, open settings); menuBarTray is part of app_shell BC but a distinct container"
    }

    views {
        systemContext k8sManager "system-context" {
            include *
            autoLayout lr
            description "Operator drives K8sManager, which speaks REST natively to the Kubernetes API server, cloud identity providers (AWS STS, Google OAuth and STS, Microsoft Entra ID, generic OIDC), Prometheus, and configured LLM providers (Anthropic, OpenAI, OpenAI-compatible). No external binary (kubectl, helm, aws, gcloud, kubelogin) is invoked except as a fallback for unknown exec plugins."
        }

        container k8sManager "containers" {
            include *
            autoLayout tb
            description "Thirteen bounded-context containers plus their adapter layer. Domain cores never import infrastructure (ADR-0011, ADR-0020). Every external system is reached via a dedicated adapter implementing a domain port."
        }

        styles {
            element "Person" {
                shape Person
                background #1168bd
                color #ffffff
            }
            element "External" {
                background #999999
                color #ffffff
            }
        }
    }
}
