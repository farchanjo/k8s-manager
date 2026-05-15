# ADR-0033 — Internationalisation (i18n) and multi-language support

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0001 (macOS native Swift), ADR-0021 (app shell design system and layout), ADR-0023
  (UX patterns — command palette and shortcuts), ADR-0026 (state persistence and filesystem layout)
- Tags — i18n, l10n, localisation, xcstrings, swiftui, pluralization, rtl, locale, community

> **Scope note (2026-05-15).** This ADR establishes the internationalisation strategy for
> K8sManager. It covers source language selection, the Xcode String Catalog (`.xcstrings`) as the
> single source of truth for UI strings, the MVP+ baseline locale set, pluralization rules, RTL
> layout design, timezone separation, key naming conventions, and the community-extensible locale
> framework. It does not cover currency handling (the app is free or paid via the macOS App Store
> and performs no currency arithmetic). It does not cover translation of Kubernetes identifiers, log
> output, or code blocks — these are infrastructure identifiers, not user-facing copy.
>
> **Language of spec artefacts.** All spec artefacts (ADRs, CUE schemas, Gherkin features, Rego
> policies, DBML, Structurizr DSL) remain in en-US. Only Xcode `.xcstrings` UI strings are
> localised.

---

## Context and problem statement

K8sManager targets macOS 14+ operators worldwide. As of the MVP+ release the application ships
exclusively in American English (en-US). While English is the de-facto language of the Kubernetes
ecosystem, a meaningful share of the target audience (Brazilians, Latin Americans, Europeans, East
Asians) are more productive in their first language for navigational copy, error messages,
onboarding text, and settings labels.

Three tensions make this non-trivial:

1. **Source language purity** — all code, comments, ADRs, schemas, and spec files must remain in
   en-US (existing convention). Localisation concerns must not bleed into the source model.

2. **Maintenance overhead** — shipping many locales simultaneously requires translator pipelines,
   quality gates, and an update discipline. An ad-hoc approach produces stale translations and
   operator-visible English fallbacks in unexpected places.

3. **Apple platform conventions** — macOS 14 mandates Xcode String Catalogs (`.xcstrings`) as the
   replacement for legacy `.strings` / `.stringsdict` files. Ignoring this would mean adopting a
   format Xcode no longer first-class supports.

The question is: which combination of locale scope, tooling, string organisation, and community
model best serves K8sManager operators while keeping the development team's overhead manageable?

## Decision drivers

- All code, comments, ADRs, and schemas must remain in en-US; localisation concerns must not bleed
  into the source model.
- macOS 14 mandates Xcode String Catalogs (`.xcstrings`) as the replacement for legacy `.strings` /
  `.stringsdict` files; ignoring this risks adopting a format Xcode no longer first-class supports.
- A meaningful share of the target audience (Brazilian, Latin American, European, East Asian
  operators) is more productive in their first language for navigational copy and error messages.
- Shipping many locales simultaneously requires translator pipelines, quality gates, and an update
  discipline that an ad-hoc approach cannot sustain.
- Key stability invariant: renaming a key must follow a two-release deprecation cycle; the
  governance model must encode this without bespoke ADR overhead per locale addition.

## Decision outcome

**Adopt Xcode String Catalogs (`.xcstrings`, macOS 14+ native format) as the single source of truth
for all user-visible UI strings. Ship MVP+ with three baseline locales (en, pt-BR, es-ES). Extend
via a community-driven PR model governed by `i18n_manifest.cue`.**

Key pillars:

- **en-US is the source language** — every translatable string originates in en-US. The `.xcstrings`
  file carries the source value and translator notes inline.
- **Baseline set (MVP+): en (en-US + en-GB), pt-BR, es-ES** — these three locales are maintained by
  the core team.
- **Extension locales** — any Apple-recognised locale may be added by a community contributor via a
  PR that updates the `.xcstrings` file and the `i18n_manifest.cue` manifest.
- **Key naming**: `<bc>.<screen>.<element>.<purpose>` (e.g.
  `resource_browser.detail.yaml_editor.apply_button.label`).
- **Pluralization** via Apple stringsdict plural-variant rules embedded in `.xcstrings`; CLDR
  categories (one / other for English; zero / one / other for Spanish; one / other for Portuguese).
- **Number / Date / Time** formatting via `Locale`-aware Foundation APIs only. No hard-coded format
  strings.
- **RTL** — designed-for: SwiftUI `.environment(\.layoutDirection, ...)` handles layout mirroring
  automatically. YAML and code editors are always LTR.
- **Timezone** — orthogonal to locale; operator selects via Settings → Time Zone; default is the
  system timezone.

---

## Considered options

### Option A — English only (single language, no i18n plumbing)

Deliver the application exclusively in en-US. No `.xcstrings`, no locale infrastructure. All UI
strings are hardcoded literal `String` values in Swift source files.

**Advantages:**

- Zero additional implementation cost.
- No risk of stale translations shipping with English fallbacks.
- No toolchain complexity (Xcode localisation workflows, `.xcstrings` editor, translator
  export/import pipeline).

**Disadvantages:**

- Permanently excludes non-English-dominant operators. Spanish and Portuguese together represent the
  majority of Latin American and Iberian developer populations.
- No migration path to localisation later without a complete string extraction refactor across all
  Swift view files.
- Apple's Xcode 15+ marks hardcoded UI strings with "Fix-it" suggestions; future Xcode versions may
  treat them as warnings.
- Accessibility: VoiceOver in languages other than English reads en-US labels with wrong phonetics,
  degrading the screen-reader experience.

**Verdict: rejected.** The cost of retrofitting i18n is significantly higher than building it in
from the start. The "zero cost" framing is false; it shifts cost to a more expensive future window.

---

### Option B — Built-in team-maintained locales (en + pt-BR + es-ES only, closed set)

Adopt `.xcstrings` and ship exactly three locales (en, pt-BR, es-ES). Explicitly declare no
community extension path. The locale set is frozen until the core team decides to add more.

**Advantages:**

- Predictable translation quality: core team owns all three locales end-to-end.
- No community PR coordination overhead for locale additions.
- Simple `i18n_manifest.cue`: exactly three entries, no `extensionLocales` array.

**Disadvantages:**

- Excludes French, German, Japanese, Chinese, Korean, Arabic, and other large developer communities
  with no upgrade path short of a new ADR.
- Community contributors who want to add their language must wait for a core team decision and
  bandwidth allocation — high friction for what is a purely additive change to a `.xcstrings` file.
- Every subsequent locale addition requires a new ADR or ADR amendment, creating governance overhead
  disproportionate to the change.

**Verdict: rejected.** The closed-set model is too inflexible given that locale addition is a
low-risk, low-coupling change. The community extension model adds minimal overhead and provides a
far better operator experience trajectory.

---

### Option C — Extensible community framework (chosen) ✓

Adopt `.xcstrings` as the canonical format. Ship three baseline locales (en, pt-BR, es-ES)
maintained by the core team. Define a lightweight community extension model: any contributor can add
a locale by submitting a PR that (a) adds the locale variant to the `.xcstrings` bundle and (b) adds
an entry to `i18n_manifest.cue` with `status: "beta"` or `"incomplete"` and a `translationCoverage`
value.

The `i18n_manifest.cue` schema is the governance contract: it records the `identifier`,
`displayName`, `translationCoverage`, `maintainer`, `addedInVersion`, and `status` for every locale.
Missing keys in an extension locale fall back to en-US strings at runtime — never blank.

**Advantages:**

- Baseline quality guaranteed for the three core locales.
- Community contributors have a clear, low-friction path.
- The `translationCoverage` field gives operators visibility into incomplete locales before they
  select them.
- `status: "incomplete"` locales display a warning banner in Settings → Language when coverage drops
  below 80%.
- Orthogonal governance: adding a locale does not require an ADR, only a PR reviewed against the
  `i18n_manifest.cue` lint rules.

**Disadvantages:**

- Community locale quality is not core-team controlled. Mitigation: the PR review checklist requires
  a minimum `translationCoverage` of 0.75 for `status: "beta"`.
- `.xcstrings` file grows with every locale. Mitigation: `.xcstrings` is a JSON dialect; growth is
  linear and Xcode handles merge conflicts cleanly.
- First-time contributors may not know the key naming convention. Mitigation: a
  `CONTRIBUTING_I18N.md` document (referenced from the PR template) explains the
  `<bc>.<screen>.<element>.<purpose>` schema.

**Verdict: chosen.**

---

## String resolution pipeline

```mermaid
graph LR
    EN["Source strings\n(en-US)\n.xcstrings"]
    TM["Translation memory\n(Xcode automatic\nsuggestions)"]
    XCS["Xcode String Catalog\n(.xcstrings variants:\npt-BR, es-ES, ...extension locales)"]
    LP["Locale.preferredLanguages[0]\nor operator override"]
    RES["SwiftUI String(localized:)\n/ .localizedStringKey\n/ Text(\"key\")"]
    FB["en-US fallback\n(missing key)"]

    EN --> TM
    TM --> XCS
    XCS --> LP
    LP --> RES
    RES --> FB
    FB --> RES
```

The resolution order at runtime is:

1. `Locale.preferredLanguages[0]` — the system's preferred locale.
2. Operator override stored in `local_persistence` under `app_shell/locale_preference`
   (`#LocalePreference.localeIdentifier`).
3. If neither produces a match for the requested key, the en-US source value is used as the hard
   fallback.

SwiftUI's `Text("key")` macro automatically resolves via this chain when the `.xcstrings` file is
included in the app bundle. No custom resolver is required for baseline cases; custom resolution
(e.g. for dynamic keys built at runtime) uses
`String(localized: LocalizedStringKey(dynamicKey), bundle: .main)`.

---

## Key naming convention

Every translatable key follows the dot-separated path:

```
<bounded_context>.<screen>.<element>.<purpose>
```

Examples:

**`app_shell.settings.language.title`** — Settings pane "Language" section title.

**`resource_browser.detail.yaml_editor.apply_button.label`** — Apply button label in YAML editor.

**`resource_browser.detail.yaml_editor.apply_button.accessibility_label`** — VoiceOver label for
Apply button.

**`cluster_connectivity.onboarding.import_kubeconfig.empty_state.title`** — Empty state title on
kubeconfig import screen.

**`cluster_connectivity.onboarding.import_kubeconfig.empty_state.description`** — Empty state
description.

**`app_shell.toast.mutation_succeeded.title`** — Toast title for successful mutation.

**`app_shell.toast.mutation_succeeded.message`** — Toast body for successful mutation.

Rules:

- All segments lowercase, underscore-separated.
- Bounded context prefix matches the directory name in `contexts/`.
- The `purpose` segment is one of: `label`, `title`, `description`, `message`, `hint`,
  `placeholder`, `accessibility_label`, `accessibility_hint`, `tooltip`.
- Pluralized keys append `.one`, `.other`, etc. — but in `.xcstrings` these are expressed as plural
  variant entries under a single key, not separate keys.
- Keys are stable identifiers; once published they are never renamed (only deprecated with a comment
  and a replacement key reference).

---

## Localizable elements

The following categories of content are localised:

- All UI labels, button titles, navigation titles.
- Modal messages (confirmation modals, alert sheets).
- Tooltip texts (`.help()` modifier).
- Error messages surfaced to the operator (including fallback to en-US).
- Toast notification titles and body messages.
- Empty state titles and descriptions.
- Onboarding tour step text (welcome, kubeconfig import, assistant introduction).
- Settings section titles and row labels.
- Accessibility labels and hints for VoiceOver (`.accessibilityLabel`, `.accessibilityHint`).
- App menu items (File, Edit, View, and application-specific menus).
- Sidebar section headers and category group labels.

The following content is explicitly **not localised**:

- Kubernetes resource names, kinds, API groups, namespaces — these are Kubernetes identifiers, not
  operator-facing copy.
- Code blocks: YAML manifests, JSON content displayed in the editor.
- Raw log output from cluster pods and nodes.
- Operator-typed search queries and filter expressions.
- Kubernetes error messages returned verbatim by the API server — these are surfaced as-is,
  optionally with a localised prefix (e.g. "Server error:").

---

## Pluralization

Apple stringsdict plural rules are embedded natively in `.xcstrings` format. Each language declares
its CLDR plural categories:

**en-US** — categories `one`, `other` — example: "1 pod", "2 pods".

**pt-BR** — categories `one`, `other` — example: "1 pod", "2 pods".

**es-ES** — categories `one`, `other` — example: "1 pod", "2 pods".

**ar** — categories `zero`, `one`, `two`, `few`, `many`, `other` — full Arabic forms.

Usage in Swift:

```swift
Text("\(count) pods", tableName: nil, bundle: .main, comment: "Pod count label")
```

The `.xcstrings` file carries the plural variant table for each supported locale. The key
`resource_browser.list.pod_count` would carry `one:` "1 pod" and `other:` "%d pods" for en-US.

---

## Number, date, and time formatting

All numeric and temporal values displayed in the UI are formatted via `Locale`-aware Foundation
APIs:

- **Numbers**: `NumberFormatter` with `numberStyle = .decimal` and `locale = Locale.current` (or the
  operator override locale).
- **Dates**: `DateFormatter` respecting `#LocalePreference.dateStyle` (short / medium / long /
  full). Default: medium.
- **Times**: `DateFormatter` respecting `#LocalePreference.timeStyle` (short / medium / long).
  Default: short.
- **Internal storage**: all timestamps stored in RFC 3339 / ISO 8601 format. The `Locale`-aware
  formatter is applied only at the presentation layer.
- **Timezone**: `TimeZone(identifier:)` resolved from `#LocalePreference.timezone`. Default:
  `"system"` which maps to `TimeZone.current`. Stored separately from locale; operator may be in
  `pt-BR` locale but `UTC` timezone.

Examples of formatted output:

```
Value                        en-US (medium date)  pt-BR (medium date)    es-ES (medium date)
---------------------------  -------------------  ---------------------  -------------------
2026-05-15T00:00:00Z         May 15, 2026         15 de mai. de 2026     15 may 2026
2026-05-15T00:00:00Z (short) 5/15/26              15/05/2026             15/5/26
1234.56                      1,234.56             1.234,56               1.234,56
```

---

## RTL layout support

RTL support is built in at design time rather than retrofitted:

- SwiftUI automatically mirrors layout when `.environment(\.layoutDirection, .rightToLeft)` is set.
  The `LocaleResolverService` sets this environment value based on the active locale's
  `Locale.Characterization.characterDirection`.
- Icons that are directional (e.g. back-arrow, chevron-right, sidebar-expand) are mirrored
  automatically via SF Symbols' built-in RTL variants.
- The YAML editor, JSON editor, log viewer, and terminal panel are permanently `leftToRight`
  regardless of the active locale. Code is always LTR.
- The sidebar, content list, and detail pane invert their column order in RTL locales (sidebar on
  the right, detail on the left).
- Arabic (ar) and Hebrew (he) are designated as RTL test targets in the community extension locale
  list. They are not baseline locales and are shipped with `status: "incomplete"` initially.

---

## Operator locale override

By default the application respects `Locale.preferredLanguages[0]`. The operator may override this
in Settings → Language:

- A picker lists all locales present in `i18n_manifest.cue` with their `displayName` (rendered in
  that locale's own script).
- Extension locales with `translationCoverage < 0.80` show a warning badge.
- Locales with `status: "incomplete"` show a distinct indicator and a note that some strings may
  appear in English.
- The selection is persisted to `local_persistence` under `app_shell/locale_preference` as a
  `#LocalePreference` value object.
- Locale changes take effect immediately without an application restart; the SwiftUI environment is
  updated reactively and the UI reloads within 200 ms.

---

## Community extension model

Any Apple-recognised locale can be added by a community contributor via a pull request that
satisfies all of the following:

1. Adds the locale variant to the relevant `.xcstrings` files covering at least 75% of all
   translatable keys (`translationCoverage >= 0.75`).
2. Adds an entry to `docs/arch/contexts/app_shell/schemas/i18n_manifest.cue` in the
   `extensionLocales` array with accurate `identifier`, `displayName` (in the target locale's own
   script), `translationCoverage`, `maintainer` (GitHub handle), `addedInVersion`, and `status`
   (typically `"beta"` for a first contribution, `"incomplete"` if below 75%).
3. Passes the CUE lint gate (`cue vet ./docs/arch/contexts/app_shell/schemas/`).
4. PR description confirms the contributor is a native or fluent speaker of the target locale or
   that the translation was reviewed by one.

The core team's review checklist for locale PRs focuses on: key completeness (`translationCoverage`
value accuracy), `displayName` correctness, and `status` accuracy. The team does not perform
linguistic review for extension locales; that responsibility rests with the community maintainer.

Locale removal: if a locale's `maintainer` is unreachable for 6 months after a major string churn
and `translationCoverage` drops below 0.50, the locale is moved to `status: "incomplete"` and the CI
gate emits a warning. The locale is never deleted; operators who selected it continue to see it with
en-US fallback for untranslated keys.

---

## Roadmap of community-proposed locales

The following extension locales are pre-registered in `i18n_manifest.cue` with
`status: "incomplete"` and `translationCoverage: 0.0`, signalling intent and reserving identifiers.
They are not shipped with any translated strings until a community contributor submits a qualifying
PR:

- `pt-PT` — Português (Portugal)
- `es-MX` — Español (México)
- `es-AR` — Español (Argentina)
- `fr-FR` — Français
- `de-DE` — Deutsch
- `it-IT` — Italiano
- `nl-NL` — Nederlands
- `pl-PL` — Polski
- `ru-RU` — Русский
- `ja-JP` — 日本語
- `ko-KR` — 한국어
- `zh-Hans` — 中文（简体）
- `zh-Hant` — 中文（繁體）
- `ar` — العربية
- `he` — עברית

`ar` and `he` additionally serve as RTL validation targets during development.

---

## String grouping by bounded context

UI strings are grouped into `.xcstrings` files per bounded context to reduce merge conflicts and
improve translator clarity:

**`app_shell.strings`** — Window chrome, toolbar, settings, toasts, menu bar.

**`cluster_connectivity.strings`** — Kubeconfig import, cluster list, health states.

**`resource_browser.strings`** — Resource list, detail pane, editor, mutations.

**`context_navigation.strings`** — Context switcher, pinned contexts, recents.

**`port_forwarding.strings`** — Port forward start, stop, status labels.

**`terminal_session.strings`** — Terminal tab labels, session lifecycle messages.

**`helm_management.strings`** — Helm release list, inspect, rollback copy.

**`metrics_observability.strings`** — Chart labels, axis labels, query error messages.

**`assistant_chat.strings`** — Chat UI, session labels, streaming indicators.

**`onboarding.strings`** — First-launch tour steps 1–3.

In Xcode 15+ each `.xcstrings` file is edited in the String Catalog editor and exported as a
`.xcloc` package for external translators. Each file maps to one String Catalog target in the Xcode
project.

---

### Consequences

Positive:

- Operators in Brazil, Spain, and Latin America receive a first-class experience from the MVP+
  release.
- The community extension model provides a clear, governed path to additional locales without core
  team bottleneck.
- `translationCoverage` and `status` fields in `i18n_manifest.cue` give operators informed choice
  before selecting an extension locale.
- RTL-designed layout prevents expensive future rework for Arabic and Hebrew operators.
- en-US fallback prevents blank strings from ever reaching the operator.
- Timezone orthogonality to locale avoids the common pitfall of conflating display language with
  display timezone.

Negative:

- Initial setup cost: all existing hardcoded UI strings must be extracted to `.xcstrings` keys
  before MVP+ ships. Estimated scope: approximately 600–900 distinct strings across all bounded
  contexts.
- Three baseline locales require initial human translation.
- Key stability invariant adds coordination overhead: renaming a key requires a two-release
  deprecation cycle.
- The `<bc>.<screen>.<element>.<purpose>` key naming scheme produces verbose key identifiers.

### Confirmation

See `## Compliance and test criteria` below for the full test matrix. Key gates:

- `LocaleResolverService` resolves `pt-BR` when `localePreference.localeIdentifier == "pt-BR"`
  regardless of the system preferred language.
- On launch with `Locale.preferredLanguages[0] == "pt-BR"`, all visible sidebar and toolbar labels
  are in Brazilian Portuguese.
- Operator changes locale to `"es-ES"` in Settings; UI updates within 200 ms without restart.
- A missing key in `pt-BR` locale renders the en-US source string, not blank.
- `cue vet ./docs/arch/contexts/app_shell/schemas/` passes cleanly on `#I18nManifest`.

---

## Compliance and test criteria

### Unit tests

- `LocaleResolverService` resolves `Locale("pt-BR")` when
  `localePreference.localeIdentifier == "pt-BR"` regardless of the system preferred language.
- `LocaleResolverService` falls back to `Locale("en-US")` when the preference localeIdentifier is
  absent from the bundle's supported locales.
- `NumberFormatter` configured with `pt-BR` locale renders `1234.56` as `"1.234,56"`.
- `DateFormatter` configured with `en-US` locale and `dateStyle = .short` renders `2026-05-15` as
  `"5/15/26"`.
- `DateFormatter` configured with `pt-BR` locale and `dateStyle = .short` renders `2026-05-15` as
  `"15/05/2026"`.
- Pluralization: `resource_browser.list.pod_count` for count=1 in en-US resolves to `"1 pod"`; for
  count=5 resolves to `"5 pods"`.

### Integration tests

- On launch with `Locale.preferredLanguages[0] == "pt-BR"`, all visible UI labels in the sidebar and
  toolbar are in Brazilian Portuguese.
- Operator changes locale in Settings → Language to `"es-ES"`; UI updates within 200 ms; no restart
  required.
- Selecting an extension locale with `translationCoverage = 0.60` shows a warning badge in the
  locale picker.
- A missing key in `pt-BR` locale renders the en-US source string (not blank, not the key
  identifier).

### CUE schema validation

- `cue vet ./docs/arch/contexts/app_shell/schemas/` passes cleanly on the `#I18nManifest` and
  `#LocalePreference` schemas.
- `translationCoverage` values are in range `[0.0, 1.0]` for all entries.
- `status` values are one of `"stable"`, `"beta"`, `"incomplete"` for all entries.

---

## Dependencies

**Xcode String Catalog (`.xcstrings`) — Xcode 15+, macOS 14+** — Primary localisation format.

**`Foundation.Locale` — System (macOS 14+)** — Locale resolution, number/date formatting.

**`Foundation.DateFormatter` — System** — Locale-aware date and time formatting.

**`Foundation.NumberFormatter` — System** — Locale-aware number formatting.

**SwiftUI `\.layoutDirection` — System (macOS 14+)** — RTL layout environment.

**`TranslationCatalogPort` — This project** — Port interface for locale resolution.

**`#LocalePreference` CUE schema — This project** — Value object for persisted locale settings.

**`#I18nManifest` CUE schema — This project** — Locale registry and governance contract.

## More information

- ADR-0001 — macOS native Swift; mandates Xcode toolchain and `.xcstrings` compatibility.
- ADR-0021 — App shell design system; typography and density preferences are locale-aware.
- ADR-0023 — UX patterns; command palette labels and shortcut descriptions are localised here.
- ADR-0026 — State persistence; `#LocalePreference` is stored under `app_shell/locale_preference`.
- `contexts/app_shell/schemas/locale_preference.cue` — value object for persisted locale settings.
- `contexts/app_shell/schemas/i18n_manifest.cue` — locale registry and governance contract.
- `contexts/app_shell/features/locale-selection.feature` — BDD scenarios for locale picker.
- `contexts/app_shell/features/pluralization-and-formatting.feature` — pluralization BDD scenarios.
- `contexts/app_shell/features/rtl-support.feature` — RTL layout BDD scenarios.
