# K8sManager — Architecture Documentation Root

Spec-as-source-of-truth for **K8sManager**, a macOS-native Kubernetes
manager with built-in LLM assistant. This directory is the single
source of truth for architectural decisions, domain schemas,
behavioural specifications, and validation policies.

## Product summary

- **Product name** — K8sManager.
- **Bundle identifier** — `com.archanjo.K8sManager`.
- **Target platform** — macOS 14 Sonoma and later.
- **UI framework** — SwiftUI with strict Swift Concurrency.
- **Kubernetes client** — SwiftkubeClient on SwiftNIO with a pooled
  HTTP client and persistent keep-alive connections.
- **Distribution** — direct download, Developer ID signed, notarized
  via `notarytool`.
- **LLM integration** — Anthropic Messages, OpenAI Chat Completions,
  and any OpenAI-compatible endpoint (Ollama, LM Studio, vLLM,
  OpenRouter).
- **MCP role** — host plus an in-process Model Context Protocol
  server that exposes read-only Kubernetes tools to the assistant.
- **Local persistence** — SQLite (WAL) for chat history, provider
  configuration, cluster-analysis cache, and operator preferences;
  macOS Keychain for LLM API keys.
- **Original MVP scope** — multi-cluster connectivity and context
  switching against the user kubeconfig.
- **Expanded MVP+ scope** — adds the assistant chat, LLM provider
  abstraction, in-process MCP server, local persistence, and
  connection pooling. See **ADR-0006** for the authoritative
  catalogue.

## Layout

```
docs/arch/
  architecture/      Structurizr C4 workspace
  decisions/         MADR 4.0 architecture decision records
  contexts/<bc>/     bounded contexts, one directory each
    schemas/         CUE definitions; SQLite DDL in DBML where applicable
    policies/        Rego validation rules
    features/        Gherkin behavioural scenarios
    domain/          ubiquitous language narratives
```

## Conventions (enforced)

- All artefacts written in **en-US**.
- **CommonMark only** — no GitHub-flavoured Markdown extensions
  (no tables, no task lists, no strikethrough, no autolinks).
- Markdown filenames use `kebab-case.md`.
- CUE filenames use `snake_case.cue`; definitions use `#PascalCase`.
- Database schemas use **DBML** (`*.dbml`), one logical schema per
  file under the relevant bounded context's `schemas/`.
- Every domain artefact carries the **DDD role header** on the
  first line:
  `// DDD role: AggregateRoot | Entity | ValueObject | DomainService | ReadModel`.
- Entity identifiers are **UUIDv7** (time-ordered, sortable).
- ADRs follow **MADR 4.0**; ADR numbers are never reused; superseded
  ADRs link forward to their successor.
- Dependency direction — **domain core never imports infrastructure**.
  Adapters depend on domain ports; the reverse is forbidden.

## Bounded contexts (MVP+)

- **cluster_connectivity** — parse kubeconfig, probe cluster health,
  expose typed clusters. Owns kubeconfig (read-only) and
  cluster-health invariants.
- **context_navigation** — track active context, recents, pinned
  items, drive context switching.
- **llm_provider** — abstract Anthropic, OpenAI, and any
  OpenAI-compatible endpoint behind a single `LLMProviderPort`.
  Owns provider profiles, sampling configuration, streaming
  contracts, and quota or rate-limit invariants.
- **assistant_chat** — sessions, messages, streaming, tool-use loop,
  attachments, and cancellation. Consumes `llm_provider` and
  `cluster_intelligence`.
- **cluster_intelligence** — translates assistant intents into safe,
  read-only Kubernetes operations through the in-process MCP server.
  Hosts the tool registry surfaced to the LLM (list, describe,
  events, logs, yaml).
- **local_persistence** — SQLite (WAL) storage for chat history,
  provider configuration, cluster-analysis cache, and operator
  preferences. macOS Keychain adapter for LLM API keys; kubeconfig
  remains untouched on disk (see ADR-0003).
- **app_shell** — window lifecycle, sidebar, menu bar, settings
  surface, chat surface.

## Decision index

- **ADR-0001** — macOS-native distribution via Swift and SwiftUI.
  Proposed.
- **ADR-0002** — SwiftkubeClient as primary Kubernetes API adapter.
  Proposed.
- **ADR-0003** — Kubeconfig is read-only; no kubeconfig credential
  persistence. Proposed; scope clarified by ADR-0010 for LLM API keys.
- **ADR-0004** — Distribution via Developer ID and notarization.
  Proposed.
- **ADR-0005** — Bounded contexts for the initial MVP.
  **Superseded by ADR-0006.**
- **ADR-0006** — MVP+ scope and the expanded bounded-context
  catalogue. Proposed. Supersedes ADR-0005.
- **ADR-0007** — Connection pool and persistent keep-alive for the
  Kubernetes API client. Proposed.
- **ADR-0008** — LLM provider abstraction over Anthropic, OpenAI,
  and OpenAI-compatible endpoints. Proposed.
- **ADR-0009** — MCP host plus an in-process MCP server exposing
  read-only Kubernetes tools. Proposed.
- **ADR-0010** — Local persistence — SQLite for non-secret state,
  macOS Keychain for LLM API keys. Proposed.
- **ADR-0011** — Swift concurrency conventions for fluid async UI.
  Proposed.

## Validation

When the spec framework is installed at `~/.claude/.work/spec-framework/`,
run `spec validate --lane fast` for the fast lane (~1.5 s) or
`spec validate` for the default lane (~10 s). Until then, artefacts
are authored to the documented conventions and validated by review.
