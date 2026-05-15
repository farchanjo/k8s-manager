workspace "K8sManager" "macOS-native Kubernetes manager with built-in LLM assistant and in-process MCP server (MVP+ per ADR-0006)." {

    model {
        operator = person "Kubernetes Operator" "Workstation user who manages one or more Kubernetes clusters and interacts with the in-app assistant."

        k8sManager = softwareSystem "K8sManager" "macOS-native Kubernetes manager with built-in assistant." {
            appShell = container "App Shell" "SwiftUI window, sidebar, menu bar, settings, chat surface." "Swift / SwiftUI"
            contextNavigation = container "Context Navigation" "Active context, recents, pinned items." "Swift"
            clusterConnectivity = container "Cluster Connectivity" "Parses kubeconfig and probes cluster health." "Swift"
            clusterIntelligence = container "Cluster Intelligence" "In-process MCP server with read-only Kubernetes tool registry and policy gate." "Swift / MCP"
            assistantChat = container "Assistant Chat" "Chat sessions, tool-use loop, MCP host." "Swift"
            llmProvider = container "LLM Provider" "Provider port abstracting Anthropic, OpenAI, OpenAI-compatible endpoints." "Swift"
            localPersistence = container "Local Persistence" "SQLite (WAL) for non-secret state; macOS Keychain adapter for LLM API keys." "Swift / GRDB / Security"
            kubernetesAdapter = container "Kubernetes Adapter" "SwiftkubeClient adapter, pooled HTTPClient (ADR-0007), exec-plugin port." "Swift / SwiftkubeClient / SwiftNIO"
            kubeconfigAdapter = container "Kubeconfig Adapter" "YAML parser over the user kubeconfig file(s)." "Swift / Yams"
            preferencesAdapter = container "Preferences Adapter" "UserDefaults overlay for transient UI preferences." "Swift / UserDefaults"
            sqliteStore = container "SQLite Storage" "WAL-mode SQLite database for chat history, profiles, cache, log, prefs." "SQLite 3 / GRDB"
            keychainAdapter = container "Keychain Adapter" "macOS Keychain (kSecClassGenericPassword) for LLM API keys." "Security framework"
        }

        kubeconfigFile = softwareSystem "Kubeconfig File" "User-managed YAML file at KUBECONFIG or ~/.kube/config." "External"
        kubernetesApi = softwareSystem "Kubernetes API Server" "Remote cluster API endpoint (one per cluster, possibly many)." "External"
        execPlugin = softwareSystem "Exec Credential Plugin" "External binary that prints an ExecCredential JSON (aws, gcloud, kubelogin, OIDC)." "External"
        anthropicApi = softwareSystem "Anthropic Messages API" "Anthropic-hosted LLM endpoint." "External"
        openaiApi = softwareSystem "OpenAI API" "OpenAI-hosted LLM endpoint." "External"
        openaiCompatible = softwareSystem "OpenAI-Compatible Endpoint" "Local or hosted server speaking the OpenAI API (Ollama, LM Studio, vLLM, OpenRouter)." "External"

        // Operator interactions
        operator -> appShell "Switches contexts, configures providers, chats with the assistant"

        // App Shell consumes read models from navigation, connectivity, and chat
        appShell -> contextNavigation "Reads ActiveContext, SidebarReadModel"
        appShell -> clusterConnectivity "Reads ClusterReadModel and KubeconfigLoadReportReadModel"
        appShell -> assistantChat "Reads OpenSessionsReadModel and LiveTurnReadModel"
        appShell -> llmProvider "Reads ProviderListReadModel via settings surface"
        appShell -> localPersistence "Reads operator preferences"

        // Navigation depends on connectivity for identifiers and on persistence for pins/recents
        contextNavigation -> clusterConnectivity "Reads ClusterReadModel"
        contextNavigation -> localPersistence "Persists pins and recents"

        // Connectivity reads kubeconfig and probes API servers via the pool
        clusterConnectivity -> kubeconfigAdapter "Loads kubeconfig (read-only)"
        clusterConnectivity -> kubernetesAdapter "Probes /readyz via pooled HTTPClient"
        kubeconfigAdapter -> kubeconfigFile "Reads YAML"
        kubernetesAdapter -> kubernetesApi "HTTPS over pooled connections (ADR-0007)"
        kubernetesAdapter -> execPlugin "Spawns and parses ExecCredential JSON, in-memory only"

        // Cluster intelligence hosts the MCP server and uses the same Kubernetes adapter pool
        clusterIntelligence -> clusterConnectivity "Reads ClusterReadModel and Kubernetes API port"
        clusterIntelligence -> kubernetesAdapter "Issues read-only verbs after policy gate"
        clusterIntelligence -> localPersistence "Persists MCP invocation log"

        // Assistant chat hosts the MCP host and consumes the provider port
        assistantChat -> llmProvider "Streams replies via LLMProviderPort"
        assistantChat -> clusterIntelligence "Executes tool calls via MCP protocol (in-process transport)"
        assistantChat -> contextNavigation "Reads pinned ContextId for the session"
        assistantChat -> localPersistence "Persists sessions, messages, tool-call records"

        // LLM provider adapter family
        llmProvider -> anthropicApi "POST /v1/messages with SSE streaming"
        llmProvider -> openaiApi "POST chat completions / responses with SSE streaming"
        llmProvider -> openaiCompatible "POST OpenAI-compatible endpoints (Ollama, LM Studio, vLLM)"
        llmProvider -> localPersistence "Reads ProviderProfile rows; resolves API key from Keychain via LLMKeyStorePort"

        // Persistence has two adapters
        localPersistence -> sqliteStore "Writes/reads via GRDB"
        localPersistence -> keychainAdapter "Stores LLM API keys"
        keychainAdapter -> kubernetesApi "(none) Keychain is local-only"

        // App shell preferences overlay
        appShell -> preferencesAdapter "Transient UI prefs (window frame)"
    }

    views {
        systemContext k8sManager "system-context" {
            include *
            autoLayout lr
            description "Operator drives K8sManager, which reads kubeconfigs, talks to Kubernetes API servers over pooled HTTPS, and streams replies from configured LLM providers."
        }

        container k8sManager "containers" {
            include *
            autoLayout tb
            description "Bounded-context containers and infrastructure adapters per ADR-0006 and ADR-0007. Domain cores never import infrastructure; all I/O crosses an adapter boundary. The assistant_chat container is the MCP host; cluster_intelligence runs the in-process MCP server (ADR-0009)."
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
