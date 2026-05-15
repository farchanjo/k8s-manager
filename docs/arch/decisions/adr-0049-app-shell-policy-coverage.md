# ADR-0049 — app_shell policy coverage (four focused Rego policies)

- Status — Accepted (ratified 2026-05-15)
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none)
- Informed — (none)
- Tags — app_shell, rego, energy, locale, single-instance, accessibility, policy
- Refines — ADR-0021 (app shell design system and layout)
- Refines — ADR-0022 (menu bar tray with live metrics)
- Refines — ADR-0033 (internationalisation multi-language)
- Refines — ADR-0042 (single-instance enforcement)

## Context and problem statement

`app_shell` is the largest bounded context in the application: 28 Gherkin feature files and 16 CUE
schemas. Despite this breadth, a cross-context audit identified that `app_shell` has zero Rego
policies. The audit flagged this as a critical gap (severity 🛑) because:

1. **Energy** — tray widget refresh intervals and background CPU behaviour on battery are specified
   in narratives and Gherkin but have no machine-enforceable invariants.
2. **Locale** — ADR-0033 and ADR-0039 define locale identifier constraints; no policy enforces them
   at the OPA evaluation layer, leaving them as documentation-only commitments.
3. **Single-instance** — ADR-0042 defines LSMultipleInstancesProhibited and the instance-lease key
   format; no policy enforces these at CI time.
4. **Accessibility** — `accessibility.feature` specifies VoiceOver and keyboard-navigation
   requirements; no machine-enforceable invariants exist for label presence, contrast ratios, or
   reading-order assertions.

Without Rego policies, these invariants can silently regress across refactors with no CI signal.

## Decision drivers

- **Machine-enforceable invariants** — narrative and Gherkin alone are insufficient for regression
  prevention; Rego policies run in CI via `conftest` and fail the build on violation.
- **Bounded scope** — each policy should cover one cohesive concern; cross-concern policies are
  harder to maintain and attribute violations to.
- **Existing schema reuse** — policies must reference field names that already exist in the CUE
  schemas (`#TrayRefreshEvent`, `#LocalePreference`, `keyboard_shortcut_map.cue`); no new schema
  fields should be invented solely for the policy.
- **Testability** — each policy must ship with a `_test.rego` file containing at least three allow
  and three deny scenarios to ensure correct evaluation.

## Considered options

1. **Skip Rego for app_shell** — maintain status quo. Rejects the audit finding; leaves 28 feature
   files and 16 schemas without machine-enforceable enforcement.
2. **Single monolithic `app_shell_policy.rego`** — consolidate all invariants into one file. Simple
   to discover; hard to maintain; deny rules across energy, locale, single-instance, and
   accessibility concerns become entangled.
3. **Four focused policies** — `energy_policy.rego`, `locale_policy.rego`,
   `single_instance_policy.rego`, `accessibility_policy.rego`. Each covers one concern; each ships
   with a companion `_test.rego`.

## Pros and cons of the options

### Option 1 — Skip Rego

- Pro: no implementation cost.
- Con: audit finding remains open; invariants are documentation-only.
- Con: regressions in energy, locale, accessibility, and single-instance behaviour produce no CI
  signal.

### Option 2 — Single monolithic policy

- Pro: one file to find.
- Con: mixing unrelated deny rules in one package makes it difficult to reason about which concern
  is violated when a rule fires.
- Con: the package namespace `app_shell` is too broad; future policies from other ADRs would collide
  or extend this file unexpectedly.
- Con: a single large file with dozens of test cases is harder to review.

### Option 3 — Four focused policies

- Pro: each policy is independently understandable and independently testable.
- Pro: concern attribution is unambiguous: an energy rule fires in `energy_policy.rego`, not
  somewhere in a monolith.
- Pro: future additions (e.g. a performance budget policy) can introduce a new focused file without
  disturbing existing policies.
- Con: four files to maintain instead of one; the operational overhead is minimal given the
  `_test.rego` companion convention.

## Decision outcome

**Chosen option: 3 — four focused policies.**

### Policy specifications

#### `energy_policy.rego` — package `k8smanager.app_shell.energy`

Input contract:

```
input.powerSource           — "battery" | "ac"
input.displaySleepActive    — bool
input.trayRefreshIntervalSec — int
input.cpuPercentSustained   — number (0–100)
```

Invariants:

- When `powerSource == "battery"`: `trayRefreshIntervalSec >= 30`.
- When `powerSource == "ac"`: `trayRefreshIntervalSec >= 5`.
- When `displaySleepActive == true`: no background CPU work is permitted; represented as
  `cpuPercentSustained == 0` in the policy input (enforced at CI time against configuration
  assertions).
- Sustained idle CPU must not exceed 1%: `cpuPercentSustained <= 1`.

#### `locale_policy.rego` — package `k8smanager.app_shell.locale`

Input contract:

```
input.localeIdentifier      — string
input.pluralizationEngine   — "Foundation.NumberFormatter" | "custom"
input.localeSwitchLatencyMs — int
```

Invariants:

- `localeIdentifier` matches `^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$` (per ADR-0039 MEDIUM-04
  sanitization).
- `pluralizationEngine` must be `"Foundation.NumberFormatter"` (no custom logic — CLDR fidelity
  required).
- `localeSwitchLatencyMs <= 50`.

#### `single_instance_policy.rego` — package `k8smanager.app_shell.single_instance`

Input contract:

```
input.lsMultipleInstancesProhibited — bool   (from Info.plist)
input.secondInstanceBehavior        — "activate-existing" | "terminate-new" | "open-new"
input.instanceLeaseKey              — string
```

Invariants:

- `lsMultipleInstancesProhibited == true`.
- `secondInstanceBehavior == "activate-existing"` (ADR-0042: second launch activates the running
  instance via `NSRunningApplication.activate`; no new window is opened).
- `instanceLeaseKey` matches `^k8smgr-instance-[a-f0-9]{16}$`.

#### `accessibility_policy.rego` — package `k8smanager.app_shell.accessibility`

Input contract:

```
input.controls[_].id                  — string
input.controls[_].accessibilityLabel  — string
input.controls[_].colorContrastRatio  — number
input.controls[_].isLargeText         — bool
input.voiceOverOrderMatchesVisual      — bool
input.keyboardNavigableActionIds       — [string]
input.shortcutMapActionIds             — [string]
```

Invariants:

- All controls have a non-empty `accessibilityLabel`.
- Color contrast ratio for body text (`isLargeText == false`) must be >= 4.5 (WCAG AA).
- Color contrast ratio for large text (`isLargeText == true`) must be >= 3.0 (WCAG AA large text).
- `voiceOverOrderMatchesVisual == true`.
- Every action in `shortcutMapActionIds` must appear in `keyboardNavigableActionIds` (all
  keyboard-navigable actions are reachable).

### Consequences

- **Positive** — four CI-enforced policies close the audit gap for `app_shell`; regressions produce
  build failures.
- **Positive** — focused package names (`k8smanager.app_shell.energy`, etc.) prevent naming
  collisions with future policy additions.
- **Positive** — each policy ships with `_test.rego` (>=3 allow, >=3 deny scenarios), ensuring
  correct evaluation before merge.
- **Negative** — policies evaluate against structured `input` objects representing runtime or
  configuration assertions; the bridging layer (converting runtime state to `input`) must be
  maintained alongside the policies.
- **Neutral** — `conftest` is already in the spec-framework toolchain (`conftest 0.68.2` via mise);
  no new tooling dependency is introduced.

### Confirmation

- `spec validate --lane full` runs all four policies via `conftest test` and reports pass/fail.
- Each `_test.rego` file has >= 3 allow tests and >= 3 deny tests; `conftest verify` must exit 0.
- CI job `lint:rego` verifies that each new `*.rego` file has a companion `_test.rego`.

## More information

- ADR-0021 — App shell design system (energy budget narrative).
- ADR-0022 — Menu bar tray with live metrics (tray refresh interval specification).
- ADR-0033 — Internationalisation (locale identifier contract, pluralization requirements).
- ADR-0039 — Locale identifier sanitization (MEDIUM-04 regex).
- ADR-0042 — Single-instance enforcement (LSMultipleInstancesProhibited, lease key format).
- WCAG 2.1 §1.4.3 (Contrast Minimum, AA: 4.5:1 body, 3:1 large text).
- New policies:
  - `docs/arch/contexts/app_shell/policies/energy_policy.rego`
  - `docs/arch/contexts/app_shell/policies/energy_policy_test.rego`
  - `docs/arch/contexts/app_shell/policies/locale_policy.rego`
  - `docs/arch/contexts/app_shell/policies/locale_policy_test.rego`
  - `docs/arch/contexts/app_shell/policies/single_instance_policy.rego`
  - `docs/arch/contexts/app_shell/policies/single_instance_policy_test.rego`
  - `docs/arch/contexts/app_shell/policies/accessibility_policy.rego`
  - `docs/arch/contexts/app_shell/policies/accessibility_policy_test.rego`
