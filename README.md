# K8sManager

**macOS-native Kubernetes manager** with a built-in LLM assistant
(Anthropic, OpenAI, OpenAI-compatible) and an in-process Model Context
Protocol (MCP) server that exposes read-only Kubernetes tools to the
assistant.

> Project status — **architecture and specification phase**. No code is
> committed yet. The repository currently holds the spec-as-source-of-truth
> under [`docs/arch/`](docs/arch/) — Architecture Decision Records (MADR
> 4.0), CUE schemas, Gherkin features, Rego policies, and a Structurizr C4
> workspace. Implementation begins after the specification stabilises.

## Why a new manager?

Existing tools (Lens, OpenLens, Headlamp) target cross-platform Electron.
K8sManager is built for operators who live on macOS and want:

- Native window chrome, menu bar, keyboard handling, drag and drop, dark
  mode, Spotlight integration.
- Sub-second cold start, idle memory under 100 MB, single binary.
- A built-in assistant that talks to **your** chosen LLM provider (cloud
  or local via Ollama / LM Studio / vLLM / OpenRouter) and reasons over
  your cluster through a strict, auditable, **read-only** Kubernetes tool
  surface — no surprises.
- 100% native — no `kubectl`, `helm`, `aws`, `gcloud`, or `kubelogin`
  subprocesses. Every protocol speaks REST API.

## Planned scope (MVP+)

Seven bounded contexts, each owning its own ubiquitous language:

- `cluster_connectivity` — parse kubeconfig, probe cluster health.
- `context_navigation` — active context, recents, pinned.
- `app_shell` — window lifecycle, sidebar, menu bar, chat surface.
- `llm_provider` — Anthropic, OpenAI, OpenAI-compatible behind one port.
- `assistant_chat` — sessions, messages, streaming, tool-use loop.
- `cluster_intelligence` — in-process MCP server with read-only K8s tools.
- `local_persistence` — SQLite (WAL) for non-secret state; macOS Keychain
  for LLM API keys.

Additional bounded contexts on the roadmap (post-spec stabilisation):
`resource_browser` (full CRUD with confirmation, paridade Lens),
`port_forwarding`, `helm_management`, `metrics_observability` (Prometheus
auto-discovery), `terminal_session` (Pod exec + Node debug via WebSocket,
multi-tab).

## Architecture in one diagram

```
+-------------------------------------------------------------+
|                          app_shell                          |
+----------------------+---------------+----------------------+
                       |               |
                       v               v
            +---------------------+   +-------------------+
            |  context_navigation |   |  assistant_chat   |
            +----------+----------+   +---+----------+----+
                       |                  |          |
                       v                  v          v
            +---------------------+   +-------+ +---------------+
            | cluster_connectivity|   | llm_  | | cluster_      |
            +----------+----------+   | prov. | | intelligence  |
                       |              +---+---+ +-------+-------+
                       |                  |             |
                       +------------------+-------------+
                                          |
                                          v
                                +---------------------+
                                |  local_persistence  |
                                +---------------------+
```

Strategic DDD bounded contexts. Hexagonal port-and-adapter dependency
direction (domain core never imports infrastructure). MADR 4.0 ADRs in
[`docs/arch/decisions/`](docs/arch/decisions/) drive every cross-cutting
choice.

## Technology stack (planned)

| Layer | Technology |
|---|---|
| Runtime | Swift 6, SwiftUI, macOS 14 Sonoma minimum |
| Kubernetes client | SwiftkubeClient (community, async/await, SwiftNIO transport) |
| Connection pool | `async-http-client` with per-cluster TLS overlays |
| LLM providers | Anthropic Messages, OpenAI Chat Completions / Responses, OpenAI-compatible |
| MCP | `modelcontextprotocol/swift-sdk` (in-process transport) |
| Local store | SQLite (WAL) via GRDB.swift; macOS Keychain for LLM API keys |
| YAML | Yams |
| Distribution | Direct download, Developer ID signed, notarized via `notarytool`; optional Homebrew Cask |

Library choices are tracked under
[`docs/arch/decisions/`](docs/arch/decisions/) and may be refined as the
specification evolves.

## Repository layout

```
.
├── README.md                        product pitch (this file)
├── LICENSE                          Apache-2.0
├── CONTRIBUTING.md                  workflow + spec-driven conventions
├── .gitignore                       Swift + Xcode + macOS
└── docs/
    └── arch/                        spec-as-source-of-truth
        ├── README.md                conventions and decision index
        ├── architecture/            Structurizr C4 workspace
        ├── decisions/               MADR 4.0 ADRs
        └── contexts/                bounded-context artefacts
            └── <bc>/
                ├── schemas/         CUE definitions (+ DBML)
                ├── policies/        Rego validation rules
                ├── features/        Gherkin scenarios
                └── domain/          ubiquitous language narrative
```

The spec under `docs/arch/` is the single source of truth. Every cross
cutting choice that survives implementation review lands in an ADR
before the code that implements it.

## Architectural decisions (current set)

The full index lives in [`docs/arch/README.md`](docs/arch/README.md).
At the time of writing the repository holds eleven proposed ADRs
covering platform choice, Kubernetes adapter, kubeconfig read-only
invariant, distribution and notarization, bounded contexts (initial and
expanded), connection pooling, LLM provider abstraction, MCP host and
in-process server, local persistence and Keychain split, and Swift
concurrency conventions.

## Roadmap

The roadmap is captured in ADRs rather than a separate document — each
new capability lands as a new ADR before the first commit of code that
implements it. The high level direction is:

1. Stabilise the MVP+ spec — finish remaining ADRs on resource browser,
   port forwarding, Helm strategy, Prometheus integration, terminal
   sessions.
2. Pin library choices after maturity audits (Swift package ecosystem
   surveys; results are inlined into the relevant ADRs).
3. Begin implementation behind a Swift Package Manager workspace that
   matches the seven bounded contexts as separate targets.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). In short — the project follows
a strict spec-driven workflow. Architectural changes go through MADR
ADRs under `docs/arch/decisions/` before any implementation work begins.

## License

Apache License 2.0. See [`LICENSE`](LICENSE) for the full text.
