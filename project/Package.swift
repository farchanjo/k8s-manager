// swift-tools-version: 6.1
import PackageDescription

// MARK: - Swift settings applied to every target

private let strictConcurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "K8sManager",
    platforms: [
        .macOS(.v14),
    ],

    // MARK: Products

    products: [
        // Executable
        .executable(
            name: "K8sManagerApp",
            targets: ["K8sManagerApp"]
        ),

        // Domain cores — library products aid Xcode module visibility
        .library(name: "SharedKernel", targets: ["SharedKernel"]),
        .library(name: "ClusterConnectivity", targets: ["ClusterConnectivity"]),
        .library(name: "ContextNavigation", targets: ["ContextNavigation"]),
        .library(name: "LLMProvider", targets: ["LLMProvider"]),
        .library(name: "AssistantChat", targets: ["AssistantChat"]),
        .library(name: "ClusterIntelligence", targets: ["ClusterIntelligence"]),
        .library(name: "LocalPersistence", targets: ["LocalPersistence"]),
        .library(name: "ResourceBrowser", targets: ["ResourceBrowser"]),
        .library(name: "PortForwarding", targets: ["PortForwarding"]),
        .library(name: "HelmManagement", targets: ["HelmManagement"]),
        .library(name: "MetricsObservability", targets: ["MetricsObservability"]),
        .library(name: "TerminalSession", targets: ["TerminalSession"]),
        .library(name: "AppShell", targets: ["AppShell"]),

        // Adapters
        .library(name: "SwiftkubeClientAdapter", targets: ["SwiftkubeClientAdapter"]),
        .library(name: "YamsKubeconfigAdapter", targets: ["YamsKubeconfigAdapter"]),
        .library(name: "KeychainAdapter", targets: ["KeychainAdapter"]),
        .library(name: "GRDBPersistenceAdapter", targets: ["GRDBPersistenceAdapter"]),
        .library(name: "AnthropicAdapter", targets: ["AnthropicAdapter"]),
        .library(name: "OpenAIAdapter", targets: ["OpenAIAdapter"]),
        .library(name: "OpenAICompatibleAdapter", targets: ["OpenAICompatibleAdapter"]),
        .library(name: "MCPSwiftSDKAdapter", targets: ["MCPSwiftSDKAdapter"]),
        .library(name: "AWSExecCredentialAdapter", targets: ["AWSExecCredentialAdapter"]),
        .library(name: "GCPExecCredentialAdapter", targets: ["GCPExecCredentialAdapter"]),
        .library(name: "AzureExecCredentialAdapter", targets: ["AzureExecCredentialAdapter"]),
        .library(name: "OIDCExecCredentialAdapter", targets: ["OIDCExecCredentialAdapter"]),
        .library(name: "SubprocessExecCredentialAdapter", targets: ["SubprocessExecCredentialAdapter"]),
        .library(name: "PrometheusQueryAdapter", targets: ["PrometheusQueryAdapter"]),
        .library(name: "WebSocketExecAdapter", targets: ["WebSocketExecAdapter"]),
        .library(name: "WebSocketPortForwardAdapter", targets: ["WebSocketPortForwardAdapter"]),
        .library(name: "CodeEditorAdapter", targets: ["CodeEditorAdapter"]),
    ],

    // MARK: External dependencies (ADR-0019 exact version pins)

    dependencies: [
        // pointfreeco/swift-dependencies — DI primitives used in domain cores
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies",
            from: "1.9.2"
        ),
        // pointfreeco/swift-concurrency-extras — test helpers
        .package(
            url: "https://github.com/pointfreeco/swift-concurrency-extras",
            from: "1.3.1"
        ),
        // apple/swift-log
        .package(
            url: "https://github.com/apple/swift-log",
            from: "1.6.3"
        ),
        // apple/swift-metrics
        .package(
            url: "https://github.com/apple/swift-metrics",
            from: "2.5.0"
        ),
        // SwiftkubeClient 0.26.0
        .package(
            url: "https://github.com/swiftkube/client",
            exact: "0.26.0"
        ),
        // swift-server/async-http-client 1.33.x
        .package(
            url: "https://github.com/swift-server/async-http-client",
            from: "1.33.0"
        ),
        // Yams — swiftkube/client 0.26.0 constrains to 5.4.0..<6.0.0.
        // ADR-0019 names 6.2.1 as preferred; downgraded until swiftkube bumps its pin.
        .package(
            url: "https://github.com/jpsim/Yams",
            from: "5.4.0"
        ),
        // GRDB 7.10.0
        .package(
            url: "https://github.com/groue/GRDB.swift",
            exact: "7.10.0"
        ),
        // SwiftAnthropic 2.2.2
        .package(
            url: "https://github.com/jamesrochabrun/SwiftAnthropic",
            exact: "2.2.2"
        ),
        // MacPaw OpenAI 0.4.9
        .package(
            url: "https://github.com/MacPaw/OpenAI",
            exact: "0.4.9"
        ),
        // modelcontextprotocol/swift-sdk 0.12.1
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk",
            exact: "0.12.1"
        ),
        // soto-project/soto 7.14.0
        .package(
            url: "https://github.com/soto-project/soto",
            exact: "7.14.0"
        ),
        // vapor/jwt-kit 5.5.0
        .package(
            url: "https://github.com/vapor/jwt-kit",
            exact: "5.5.0"
        ),
        // apple/swift-crypto 4.5.0
        .package(
            url: "https://github.com/apple/swift-crypto",
            exact: "4.5.0"
        ),
        // AzureAD/microsoft-authentication-library-for-objc 2.11.0
        .package(
            url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc",
            exact: "2.11.0"
        ),
        // openid/AppAuth-iOS 2.0.0
        .package(
            url: "https://github.com/openid/AppAuth-iOS",
            exact: "2.0.0"
        ),
        // mchakravarty/CodeEditorView — latest tag is 0.15.4 (no 0.16.x release yet).
        // ADR-0019 names 0.16.x as the target pin; tracking upstream until tag exists.
        .package(
            url: "https://github.com/mchakravarty/CodeEditorView",
            from: "0.15.4"
        ),
    ],

    // MARK: Targets

    targets: [

        // ── Domain cores ─────────────────────────────────────────────────────

        .target(
            name: "SharedKernel",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/SharedKernel",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "ClusterConnectivity",
            dependencies: [
                "SharedKernel",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/ClusterConnectivity",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "ContextNavigation",
            dependencies: [
                "SharedKernel",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/ContextNavigation",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "LLMProvider",
            dependencies: [
                "SharedKernel",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/LLMProvider",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "AssistantChat",
            dependencies: [
                "SharedKernel",
                "LLMProvider",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/AssistantChat",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "ClusterIntelligence",
            dependencies: [
                "SharedKernel",
                "ClusterConnectivity",
                "AssistantChat",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/ClusterIntelligence",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "LocalPersistence",
            dependencies: [
                "SharedKernel",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/LocalPersistence",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "ResourceBrowser",
            dependencies: [
                "SharedKernel",
                "ClusterConnectivity",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/ResourceBrowser",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "PortForwarding",
            dependencies: [
                "SharedKernel",
                "ClusterConnectivity",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/PortForwarding",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "HelmManagement",
            dependencies: [
                "SharedKernel",
                "ClusterConnectivity",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/HelmManagement",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "MetricsObservability",
            dependencies: [
                "SharedKernel",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
            ],
            path: "Sources/MetricsObservability",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "TerminalSession",
            dependencies: [
                "SharedKernel",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/TerminalSession",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "AppShell",
            dependencies: [
                "SharedKernel",
                "ClusterConnectivity",
                "ContextNavigation",
                "LLMProvider",
                "AssistantChat",
                "ClusterIntelligence",
                "LocalPersistence",
                "ResourceBrowser",
                "PortForwarding",
                "HelmManagement",
                "MetricsObservability",
                "TerminalSession",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/AppShell",
            swiftSettings: strictConcurrencySettings
        ),

        // ── Adapters ──────────────────────────────────────────────────────────

        .target(
            name: "SwiftkubeClientAdapter",
            dependencies: [
                "ClusterConnectivity",
                "ResourceBrowser",
                "PortForwarding",
                "HelmManagement",
                .product(name: "SwiftkubeClient", package: "client"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/SwiftkubeClientAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "YamsKubeconfigAdapter",
            dependencies: [
                "SharedKernel",
                "ClusterConnectivity",
                .product(name: "Yams", package: "Yams"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/YamsKubeconfigAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "KeychainAdapter",
            dependencies: [
                "LLMProvider",
                "LocalPersistence",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/KeychainAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "GRDBPersistenceAdapter",
            dependencies: [
                "LocalPersistence",
                "AssistantChat",
                "ResourceBrowser",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/GRDBPersistenceAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "AnthropicAdapter",
            dependencies: [
                "LLMProvider",
                .product(name: "SwiftAnthropic", package: "SwiftAnthropic"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/AnthropicAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "OpenAIAdapter",
            dependencies: [
                "LLMProvider",
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/OpenAIAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "OpenAICompatibleAdapter",
            dependencies: [
                "LLMProvider",
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/OpenAICompatibleAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "MCPSwiftSDKAdapter",
            dependencies: [
                "ClusterIntelligence",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/MCPSwiftSDKAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "AWSExecCredentialAdapter",
            dependencies: [
                "ClusterConnectivity",
                // SotoCore is brought in transitively by SotoSTS (soto monorepo).
                .product(name: "SotoSTS", package: "soto"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/AWSExecCredentialAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "GCPExecCredentialAdapter",
            dependencies: [
                "ClusterConnectivity",
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/GCPExecCredentialAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "AzureExecCredentialAdapter",
            dependencies: [
                "ClusterConnectivity",
                .product(name: "MSAL", package: "microsoft-authentication-library-for-objc"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/AzureExecCredentialAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "OIDCExecCredentialAdapter",
            dependencies: [
                "ClusterConnectivity",
                .product(name: "AppAuth", package: "AppAuth-iOS"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/OIDCExecCredentialAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "SubprocessExecCredentialAdapter",
            dependencies: [
                "ClusterConnectivity",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/SubprocessExecCredentialAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "PrometheusQueryAdapter",
            dependencies: [
                "MetricsObservability",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/PrometheusQueryAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "WebSocketExecAdapter",
            dependencies: [
                "TerminalSession",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/WebSocketExecAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "WebSocketPortForwardAdapter",
            dependencies: [
                "PortForwarding",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/WebSocketPortForwardAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        .target(
            name: "CodeEditorAdapter",
            dependencies: [
                "ResourceBrowser",
                "AppShell",
                .product(name: "CodeEditorView", package: "CodeEditorView"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/CodeEditorAdapter",
            swiftSettings: strictConcurrencySettings
        ),

        // ── Executable ────────────────────────────────────────────────────────

        .executableTarget(
            name: "K8sManagerApp",
            dependencies: [
                // Domain cores
                "SharedKernel",
                "ClusterConnectivity",
                "ContextNavigation",
                "LLMProvider",
                "AssistantChat",
                "ClusterIntelligence",
                "LocalPersistence",
                "ResourceBrowser",
                "PortForwarding",
                "HelmManagement",
                "MetricsObservability",
                "TerminalSession",
                "AppShell",
                // Adapters
                "SwiftkubeClientAdapter",
                "YamsKubeconfigAdapter",
                "KeychainAdapter",
                "GRDBPersistenceAdapter",
                "AnthropicAdapter",
                "OpenAIAdapter",
                "OpenAICompatibleAdapter",
                "MCPSwiftSDKAdapter",
                "AWSExecCredentialAdapter",
                "GCPExecCredentialAdapter",
                "AzureExecCredentialAdapter",
                "OIDCExecCredentialAdapter",
                "SubprocessExecCredentialAdapter",
                "PrometheusQueryAdapter",
                "WebSocketExecAdapter",
                "WebSocketPortForwardAdapter",
                "CodeEditorAdapter",
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/K8sManagerApp",
            swiftSettings: strictConcurrencySettings
        ),

        // ── Test targets ─────────────────────────────────────────────────────

        .testTarget(
            name: "SharedKernelTests",
            dependencies: [
                "SharedKernel",
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/SharedKernelTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "ClusterConnectivityTests",
            dependencies: [
                "ClusterConnectivity",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/ClusterConnectivityTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "ContextNavigationTests",
            dependencies: [
                "ContextNavigation",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/ContextNavigationTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "LLMProviderTests",
            dependencies: [
                "LLMProvider",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/LLMProviderTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "AssistantChatTests",
            dependencies: [
                "AssistantChat",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/AssistantChatTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "ClusterIntelligenceTests",
            dependencies: [
                "ClusterIntelligence",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/ClusterIntelligenceTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "LocalPersistenceTests",
            dependencies: [
                "LocalPersistence",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/LocalPersistenceTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "ResourceBrowserTests",
            dependencies: [
                "ResourceBrowser",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/ResourceBrowserTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "PortForwardingTests",
            dependencies: [
                "PortForwarding",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/PortForwardingTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "HelmManagementTests",
            dependencies: [
                "HelmManagement",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/HelmManagementTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "MetricsObservabilityTests",
            dependencies: [
                "MetricsObservability",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/MetricsObservabilityTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "TerminalSessionTests",
            dependencies: [
                "TerminalSession",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/TerminalSessionTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "AppShellTests",
            dependencies: [
                "AppShell",
                "ClusterConnectivity",
                "SharedKernel",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            path: "Tests/AppShellTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "YamsKubeconfigAdapterTests",
            dependencies: [
                "YamsKubeconfigAdapter",
                "ClusterConnectivity",
                "SharedKernel",
            ],
            path: "Tests/YamsKubeconfigAdapterTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "SwiftkubeClientAdapterTests",
            dependencies: [
                "SwiftkubeClientAdapter",
                "ClusterConnectivity",
                "SharedKernel",
            ],
            path: "Tests/SwiftkubeClientAdapterTests",
            swiftSettings: strictConcurrencySettings
        ),

        .testTarget(
            name: "ClusterConnectivityIntegrationTests",
            dependencies: [
                "YamsKubeconfigAdapter",
                "SwiftkubeClientAdapter",
                "ClusterConnectivity",
                "SharedKernel",
            ],
            path: "Tests/ClusterConnectivityIntegrationTests",
            swiftSettings: strictConcurrencySettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
