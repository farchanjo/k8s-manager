# K8sManager Spec Conventions

Canonical convention reference for all artefacts under `docs/arch/`. Validation tooling targets this
document as the authoritative source of truth. Every convention listed here is enforced by
`scripts/validate-spec.sh` and `scripts/validate-spec-fast.sh`.

## Language

All artefacts must be written in **en-US**. This includes:

- Markdown prose (ADRs, narratives, lifecycle docs, event-flow docs)
- CUE field names and comments
- Rego rule names and comments
- Gherkin scenario text, step text, and tags
- DBML table names, column names, and notes

Non-ASCII characters are rejected by the GFM-table sentinel pass. Allowed exceptions: quoted
technical strings from external systems (e.g., Kubernetes API group paths, Unicode code points in
test data).

## Filenames

All filenames under `docs/arch/` must use **kebab-case**:

- Allowed characters: `a-z`, `0-9`, `-`, `.`
- Prohibited: uppercase letters (`A-Z`), underscores (`_`), spaces

Examples:

- Correct: `cluster-session-lifecycle.feature`, `adr-0001-macos-native-swift.md`
- Wrong: `ClusterSession.feature`, `adr_0001.md`

Exception: CUE filenames use `snake_case.cue` because CUE package conventions require it. Rego
filenames may use underscores by convention. Only markdown filenames are strictly kebab-case.

## Markup dialect

Artefacts inside `docs/arch/` use **CommonMark + Mermaid only**.

Prohibited GFM extensions (cause validation failure):

- Pipe tables (`| col | col |`)
- Task lists (`- [x]`, `- [ ]`)
- Strikethrough (`~~text~~`)
- Autolinks (bare `https://...` without angle brackets)
- Footnotes (`[^1]`)
- Alerts (`> [!NOTE]`)

Permitted Mermaid usage:

- Fenced code blocks with language tag ` ```mermaid `
- Graph, sequence, state machine, C4 context, ER diagram types
- No inline Mermaid; always fenced

Tables are permitted only in the repo root `README.md` and `CONTRIBUTING.md`, which are not governed
by this convention.

## MADR 4.0 ADR structure

Every ADR file at `decisions/adr-NNNN-<slug>.md` must contain all four required sections in this
order:

```
## Context and problem statement
## Decision drivers
## Decision outcome
## More information
```

Optional standard sections (allowed but not required):

```
## Considered options
## Pros and cons of the options
```

ADR numbers are never reused. A superseded ADR keeps its number and links forward to the successor
ADR with the line: `Superseded by [ADR-NNNN](adr-NNNN-<slug>.md).`

Full MADR 4.0 template:

```markdown
# ADR-NNNN — <title>

- Status — Proposed | Accepted | Deprecated | Superseded
- Date — YYYY-MM-DD
- Deciders — <names>
- Consulted — <names or "(none)">
- Informed — <names or "(none)">
- Tags — <comma-separated keywords>

## Context and problem statement

<Describe the context and the problem.>

## Decision drivers

- <driver 1>
- <driver 2>

## Considered options

- **Option A** — <description>
- **Option B** — <description>

## Decision outcome

Chosen option — **Option X**, because <reason>.

### Consequences

- **Positive** — <outcome>
- **Negative** — <trade-off>

## Pros and cons of the options

### Option A

- Pro: <reason>
- Con: <reason>

### Option B

- Pro: <reason>
- Con: <reason>

## More information

<Links, references, related ADRs.>
```

## DDD-role header

Every domain artefact must carry a **DDD-role header** on its first line. This requirement applies
to:

- `.cue` files — use `// DDD role: <role>`
- `.rego` files — use `# DDD role: <role>`
- `.feature` files — use `# DDD role: <role>`

Allowed role values:

- `AggregateRoot`
- `Entity`
- `ValueObject`
- `DomainService`
- `ReadModel`
- `Policy`
- `DomainEvent`

Examples:

```cue
// DDD role: AggregateRoot
package cluster_connectivity
```

```rego
# DDD role: Policy
package cluster_connectivity.kubeconfig_validation
```

```gherkin
# DDD role: Policy
Feature: Load and validate kubeconfig
```

Artefacts in `_shared/` follow the same rule; their role is typically `DomainEvent`, `ValueObject`,
or `DomainService`.

## Entity identifiers

All entity and aggregate identifiers must use **UUIDv7** (time-ordered, sortable, RFC 9562
compliant). UUIDv4 is prohibited for new entities. Existing external identifiers from third-party
systems (Kubernetes UIDs, Helm release names) retain their original format.

CUE representation:

```cue
#EntityId: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
```

## Dependency direction

Domain core must never import infrastructure. The enforced dependency hierarchy from innermost to
outermost is:

```
Domain core (entities, value objects, domain services, ports)
  <- Application services (use cases, command/query handlers)
    <- Adapters (infrastructure implementations, UI, persistence)
      <- Composition root (wiring, DI, main entry point)
```

In SwiftPM terms (see ADR-0020):

- `K8sManagerDomain` target has zero external dependencies.
- `K8sManagerApplication` depends only on `K8sManagerDomain`.
- Infrastructure targets (`K8sManagerInfra*`) depend on `K8sManagerApplication` and external
  libraries.
- The app target wires everything at startup.

Violations are caught at compile time through SwiftPM target dependency declarations. Architecture
conformance is also asserted in CUE schemas via package import rules.

## DBML schema conventions

- One logical schema per `.dbml` file, co-located under the relevant bounded context's `schemas/`
  directory.
- Table names use `snake_case`.
- Column names use `snake_case`.
- Every table includes a `created_at` timestamp column.
- Primary keys use `id` with UUIDv7 values stored as `TEXT`.
- Foreign keys are declared explicitly with `ref:` notation.
- Indexes are declared at the table level with `[indexes]`.

## CUE schema conventions

- Package names match the bounded context directory name (e.g., `package cluster_connectivity`).
- Definition names use `#PascalCase`.
- Field names use `snake_case` to match the SQLite column convention.
- Disjunctions for enum-like fields use string literals: `"active" | "inactive" | "error"`.
- Optional fields use the `?` suffix: `field?: string`.
- Mandatory constraint fields use `=~` for regex, `>` for numeric bounds.

## Rego policy conventions

- Package names mirror the bounded context and policy name:
  `package cluster_connectivity.kubeconfig_validation`.
- Every rule set must have at least one `deny` or `allow` rule.
- `import rego.v1` is required at the top of every file (after the DDD-role header and package
  declaration).
- Test rules live in a sibling `*_test.rego` file (not enforced by Lane 2 but expected for Lane 3
  integration mock).

## Gherkin feature conventions

- Feature title matches the file basename with hyphens replaced by spaces.
- Scenario titles are imperative: "Load kubeconfig from default path".
- Background steps are allowed for shared setup within a feature file.
- Tags use `@kebab-case` format.
- Scenario Outline uses `<angle-bracket>` placeholders in step text and an `Examples:` table.
- Every Scenario must have at least one `When` step and one `Then` step.
- `And` and `But` are allowed as continuation steps but not as first steps.

## Structurizr DSL conventions

- `workspace.dsl` is the single workspace file; no includes or externals.
- View keys use `PascalCase`.
- Element tags use `snake_case`.
- Every software system and container must have a `description` property.
- Relationships must have a technology property when the protocol is non-obvious (e.g.,
  `"WebSocket, v5.channel.k8s.io"`).
