# K8S-Manager — Swift Package

This directory contains the Apple platform source root for K8S-Manager. It is a pure Swift Package
(no `.xcodeproj`); Xcode opens it via `Package.swift`.

## Module topology

```
Foundation / Swift stdlib
        │
  ┌─────┴──────┐
  │ SharedKernel│  (zero external deps beyond swift-log)
  └─────┬──────┘
        │
  Domain cores (depend only on SharedKernel + swift-{dependencies,log,metrics})
  ┌─────────────────────────────────────────────────────────────────────────┐
  │ ClusterConnectivity  ContextNavigation  LLMProvider  AssistantChat      │
  │ ClusterIntelligence  LocalPersistence   ResourceBrowser                 │
  │ PortForwarding       HelmManagement     MetricsObservability            │
  │ TerminalSession                                                          │
  └──────────────────────────────┬──────────────────────────────────────────┘
                                 │
  AppShell (SwiftUI shell — imports all domain cores; NO adapter imports)
                                 │
  Adapters (each imports ONE infra lib + its domain core(s))
  ┌─────────────────────────────────────────────────────────────────────────┐
  │ SwiftkubeClientAdapter   YamsKubeconfigAdapter   KeychainAdapter        │
  │ GRDBPersistenceAdapter   AnthropicAdapter        OpenAIAdapter          │
  │ OpenAICompatibleAdapter  MCPSwiftSDKAdapter      AWSExecCredentialAdapter│
  │ GCPExecCredentialAdapter AzureExecCredentialAdapter                     │
  │ OIDCExecCredentialAdapter SubprocessExecCredentialAdapter               │
  │ PrometheusQueryAdapter   WebSocketExecAdapter    WebSocketPortForwardAdapter│
  │ CodeEditorAdapter                                                        │
  └──────────────────────────────┬──────────────────────────────────────────┘
                                 │
  K8sManagerApp (executable — composition root; imports everything)
```

The invariants above (domain cores never import infra; AppShell never imports adapters) are enforced
by `scripts/check-dependency-invariants.py` in CI (see ADR-0020).

## Architecture references

- **ADR-0019** — `docs/decisions/` — dependency version pins
- **ADR-0020** — `docs/decisions/` — target graph invariants and CI enforcement

## Build commands

```bash
# Resolve and fetch all dependencies (run from project/)
swift package resolve

# Build the full package (after source agents land Sources/ and Tests/)
swift build

# Run all tests
swift test

# Show the resolved dependency graph
swift package show-dependencies

# Run the ADR-0020 CI guard (requires swift package resolve first)
python3 scripts/check-dependency-invariants.py
```

## Opening in Xcode

```bash
# Either of the following opens the package in Xcode:
xed Package.swift
open Package.swift
```

## Source layout

```
project/
├── Package.swift                    # SwiftPM manifest (swift-tools-version 6.1)
├── .swift-version                   # Toolchain pin: 6.1
├── scripts/
│   └── check-dependency-invariants.py
├── Sources/
│   ├── SharedKernel/
│   ├── ClusterConnectivity/
│   ├── ContextNavigation/
│   ├── LLMProvider/
│   ├── AssistantChat/
│   ├── ClusterIntelligence/
│   ├── LocalPersistence/
│   ├── ResourceBrowser/
│   ├── PortForwarding/
│   ├── HelmManagement/
│   ├── MetricsObservability/
│   ├── TerminalSession/
│   ├── AppShell/
│   ├── SwiftkubeClientAdapter/
│   ├── YamsKubeconfigAdapter/
│   ├── KeychainAdapter/
│   ├── GRDBPersistenceAdapter/
│   ├── AnthropicAdapter/
│   ├── OpenAIAdapter/
│   ├── OpenAICompatibleAdapter/
│   ├── MCPSwiftSDKAdapter/
│   ├── AWSExecCredentialAdapter/
│   ├── GCPExecCredentialAdapter/
│   ├── AzureExecCredentialAdapter/
│   ├── OIDCExecCredentialAdapter/
│   ├── SubprocessExecCredentialAdapter/
│   ├── PrometheusQueryAdapter/
│   ├── WebSocketExecAdapter/
│   ├── WebSocketPortForwardAdapter/
│   ├── CodeEditorAdapter/
│   └── K8sManagerApp/
└── Tests/
    ├── SharedKernelTests/
    ├── ClusterConnectivityTests/
    ├── ContextNavigationTests/
    ├── LLMProviderTests/
    ├── AssistantChatTests/
    ├── ClusterIntelligenceTests/
    ├── LocalPersistenceTests/
    ├── ResourceBrowserTests/
    ├── PortForwardingTests/
    ├── HelmManagementTests/
    ├── MetricsObservabilityTests/
    └── TerminalSessionTests/
```

## Swift language mode

The package mandates Swift 6 (`swiftLanguageModes: [.v6]`). All targets enable `StrictConcurrency`
via:

```swift
swiftSettings: [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableExperimentalFeature("StrictConcurrency"),
]
```
