# Contributing to K8sManager

Thanks for the interest. K8sManager follows a strict **spec-driven**
workflow — the specification under [`docs/arch/`](docs/arch/) is the
single source of truth and changes there land **before** any
implementation work.

## Status

The repository is currently in the architecture and specification
phase. No code has been committed yet. If you want to contribute,
your highest-leverage contribution is review and discussion of the
Architecture Decision Records (MADR 4.0) under
[`docs/arch/decisions/`](docs/arch/decisions/).

## Workflow

### Architectural changes

Anything that affects how bounded contexts interact, what an adapter
talks to, where a port lives, or what an invariant requires lands as a
new ADR.

1. Open an issue describing the problem and the option space.
2. Draft a new ADR under `docs/arch/decisions/adr-NNNN-kebab-case.md`
   following the MADR 4.0 template (look at the existing ADRs for the
   exact shape).
3. Open a pull request. The ADR moves through `Proposed → Accepted` in
   the same PR that introduces the code which implements it (or, for
   pure architecture, in its own PR).
4. ADR numbers are **never reused**. If an ADR is later superseded,
   update its status to `Superseded by ADR-XXXX` and link forward.

### Conventions

- All artefacts are written in **en-US**, CommonMark only (no
  GitHub-flavoured Markdown extensions). Tables, task lists, and
  autolinks are reserved for the repository root files
  (`README.md`, this file, `CODE_OF_CONDUCT.md`).
- Markdown filenames use `kebab-case.md`.
- CUE filenames use `snake_case.cue`; definitions use `#PascalCase`.
- Database schemas use **DBML** (`*.dbml`).
- Every domain artefact carries a DDD role header on the first line —
  `// DDD role: AggregateRoot | Entity | ValueObject | DomainService | ReadModel`.
- Entity identifiers are **UUIDv7** (time-ordered, sortable).
- Dependency direction — the domain core never imports
  infrastructure. Adapters depend on domain ports; the reverse is
  forbidden.

### Commit messages

Conventional Commits:

```
<type>(<scope>): <subject>

[body]

[footer]
```

Examples:

- `docs(adr): add ADR-0012 mutating operations policy`
- `feat(cluster_connectivity): add ClusterHealthProbe domain service`
- `chore(spec): regenerate Structurizr workspace render`

Allowed types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`,
`build`, `ci`, `perf`, `style`, `revert`.

Break commits into small, contextual units. Avoid mega-commits that
mix unrelated changes.

### Pull request expectations

- Reference the relevant ADR(s) in the description.
- Keep the diff focused. A PR that adds a new bounded context, an
  ADR, and an unrelated refactor is three PRs.
- Update [`docs/arch/README.md`](docs/arch/README.md) if you add or
  rename a bounded context or an ADR.
- Run the spec validator when the framework is installed locally —
  `spec validate --lane fast` for fast feedback,
  `spec validate` for the default lane,
  `spec validate --lane full` for the CI lane. While the framework is
  not yet installed, validation happens by review only.

## Communication

Open an issue for design discussion, bug reports, or features.
Discussions on Slack, X, or anywhere else are not actionable until
captured in an issue or ADR.

## License

By contributing you agree that your work is licensed under the
[Apache License 2.0](LICENSE).
