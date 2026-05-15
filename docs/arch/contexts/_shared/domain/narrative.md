# Shared Kernel

The `_shared` directory is the **shared kernel** of K8sManager. It contains value objects that are
used across bounded contexts and that are explicitly exempt from the "each context owns its own
types" rule. Expanding the shared kernel is a deliberate architectural act governed by ADR-0005.

## Scope

The shared kernel contains only fully immutable value objects:

- **Identifier types** (`#ClusterId`, `#ContextId`, `#ProviderProfileId`, `#EditorSessionId`) —
  UUIDv7 wrappers that are time-ordered and globally unique. Each bounded context imports only the
  identifier it needs, never the full aggregate.
- **Primitive constraints** (`#UUIDv7`, `#RFC3339`, `#KubeconfigPath`) — string constraints that
  multiple contexts apply independently.

## Rules

- No aggregate root, entity with mutable state, or domain service may appear in the shared kernel.
- No infrastructure type (HTTPClient, GRDB pool, URLSession) may appear here.
- Every type in this directory carries the `// DDD role: ValueObject` header on the first line.
- A type added to the shared kernel must appear in at least two bounded contexts; otherwise it
  belongs to the originating context only.
- Removing or changing the type of an existing field requires an ADR amendment to ADR-0005 and a
  migration path for all consumers.

## Relationship to ADR-0005

ADR-0005 introduced the shared kernel concept for the three MVP bounded contexts
(`cluster_connectivity`, `context_navigation`, `app_shell`). The current catalogue in
`shared_kernel.cue` reflects the MVP+ expansion from ADR-0006, which added `#ProviderProfileId` (for
`llm_provider` and `assistant_chat`) and `#EditorSessionId` (for `resource_browser`). Future
expansions must reference this file.
