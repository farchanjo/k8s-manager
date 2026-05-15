# ADR-0039 — i18n locale identifier sanitization

- Status — Accepted (ratified 2026-05-15)
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0033 (internationalisation and multi-language support)
- Tags — i18n, security, injection, sqlite, locale, bcp47, sanitization, MEDIUM-04

## Context and problem statement

ADR-0033 introduced `#LocalePreference.localeIdentifier` as an operator-configurable string stored
in SQLite and subsequently passed to `Foundation.Locale` for UI rendering. The `localeIdentifier`
field accepts any `string` value in the current CUE schema, which creates an injection surface:

- ICU keyword extensions (e.g. `en-US@calendar=buddhist;numbers=arab`) alter the behavior of
  `Foundation.Locale` and `Foundation.DateFormatter` in ways the application does not anticipate,
  potentially producing garbled or adversarially crafted output in date, number, and plural
  contexts.
- A path-traversal-shaped locale string (e.g. `../../etc/passwd`) could, in theory, be passed to a
  locale-file lookup on a future macOS SDK that resolves locale resources from disk.
- Overlong or control-character-containing strings could cause downstream formatting APIs to behave
  unpredictably.

The risk materialises if an attacker gains write access to the SQLite database (e.g. via a
compromised backup restore, or a future migration bug that accepts unsanitized input), or if a
community-contributed locale entry in a malicious PR contains a non-standard identifier.

The problem: how does K8sManager ensure that only well-formed BCP 47 locale identifiers (without ICU
keyword extensions) reach `Foundation.Locale`, regardless of what is stored in SQLite?

## Decision drivers

- The `localeIdentifier` field must be validated against a strict regex before passing to
  `Foundation.Locale`.
- ICU keyword extensions (the `@key=value` suffix) must be rejected outright, not silently stripped.
- The validation must occur in `LocaleResolverService` at resolution time, not only at write time,
  to catch any value that bypasses the write-path validation (e.g. direct SQLite modification).
- A mismatch against the compiled `.xcstrings` manifest must trigger fallback to `en-US`, not a
  crash.
- The CUE schema for `#LocalePreference` must encode the constraint so that the spec lint gate
  catches non-conforming values.

## Considered options

- **Option A** — Regex-validate the stored identifier at resolution time; reject non-conforming
  values with fallback to `en-US`.
- **Option B** — Strip ICU keyword extensions silently before passing to `Foundation.Locale` (e.g.
  truncate at the `@` character).
- **Option C** — Accept any string; rely on `Foundation.Locale`'s own validation to reject bad
  inputs.

## Pros and cons of the options

### Option A — Regex-validate at resolution time; reject with fallback to en-US (chosen)

- Good, because the rejection is explicit and logged; the operator sees a predictable fallback to
  `en-US` rather than a silently wrong locale or a crash.
- Good, because the BCP 47 subset regex is encoded in the CUE schema, making the constraint
  machine-checkable at spec-lint time rather than only at runtime.
- Bad, because any valid BCP 47 locale not covered by the regex subset (e.g., locales with script
  subtags beyond the two captured groups) will be incorrectly rejected; the subset must be updated
  if broader BCP 47 coverage is needed.

### Option B — Strip ICU keyword extensions silently before passing to `Foundation.Locale`

- Good, because it avoids storing the rejected identifier; the sanitized value is immediately usable
  without requiring the caller to handle a rejection path.
- Bad, because silent stripping can produce a semantically different locale than the one the
  operator intended — for example, stripping `@calendar=buddhist` from `th-TH@calendar=buddhist`
  yields `th-TH`, which uses a different calendar system.

### Option C — Accept any string; rely on `Foundation.Locale`'s own validation

- Good, because it requires zero custom validation code; `Foundation.Locale` handles invalid inputs
  internally.
- Bad, because `Foundation.Locale` does not guarantee rejection of all invalid identifiers; some
  malformed strings are accepted silently and produce undefined locale behavior.
- Bad, because it provides no security guarantee against injection of unexpected ICU keyword
  extensions or locale tags that exploit locale-sensitive string comparison.

## Decision outcome

Chosen option — **Option A**, because silent stripping (Option B) can produce a different locale
than the one the operator intended (e.g. stripping `@calendar=buddhist` from
`th-TH@calendar=buddhist` yields `th-TH`, which uses a different calendar system — a silent semantic
change). Option C provides no security guarantee.

### Locale identifier constraint

A stored `localeIdentifier` value is valid if and only if it matches the following BCP 47 subset
regex:

```
^[a-zA-Z]{2,3}(-[A-Za-z]{2,4})?(-[A-Za-z]{4})?$
```

This pattern accepts:

- A primary language subtag of 2 or 3 ASCII letters (e.g. `en`, `pt`, `zh`).
- An optional region or extended language subtag of 2 to 4 ASCII letters (e.g. `-US`, `-BR`,
  `-Hans`).
- An optional script subtag of exactly 4 ASCII letters (e.g. `-Hant`).

The pattern explicitly excludes:

- Numeric region codes (e.g. `es-419`) — not used by Apple's locale list.
- Private-use extensions (`-x-...`).
- ICU keyword extensions (`@key=value`).
- Variant subtags beyond the two optional components above.
- Any character that is not an ASCII letter or the hyphen separator.

All locale identifiers in `#I18nManifest.supportedLocales` are valid under this regex. Any
identifier that fails the regex is rejected with a fallback to `en-US` and an `os_log` warning.

### LocaleResolverService validation contract

`LocaleResolverService` performs the following steps on every resolution cycle (application launch
and operator locale change):

1. Read the stored `localeIdentifier` string from SQLite.
2. Validate against the BCP 47 subset regex above. If the value fails, log a warning and substitute
   `en-US`.
3. Verify the validated identifier is present in the compiled `.xcstrings` manifest (via
   `Bundle.main.localizations`). If absent, log a warning and substitute `en-US`.
4. Construct `Foundation.Locale(identifier: validatedIdentifier)`.
5. Inject the resolved `Locale` into the SwiftUI environment.

Steps 2 and 3 together ensure that only identifiers known to both the regex and the app bundle's
locale manifest reach `Foundation.Locale`.

### CUE schema update

The `#LocalePreference.localeIdentifier` field in `contexts/app_shell/schemas/locale_preference.cue`
is constrained by the BCP 47 subset regex:

```
localeIdentifier: =~"^[a-zA-Z]{2,3}(-[A-Za-z]{2,4})?(-[A-Za-z]{4})?$" | *"en-US"
```

The default value `en-US` satisfies the constraint.

### Consequences

- **Positive** — ICU keyword injection is structurally prevented; a compromised SQLite value cannot
  alter locale resolution behavior beyond the well-defined BCP 47 subset; the fallback to `en-US` is
  safe and deterministic.
- **Negative** — Numeric region codes (e.g. `es-419` for Latin American Spanish) are rejected. If
  any future locale addition requires such a code, this ADR must be amended. Currently no locale in
  `#I18nManifest.supportedLocales` uses numeric regions.
- **Neutral** — The regex is intentionally narrow. Operators who attempt to set a locale via direct
  SQLite manipulation (a supported but undocumented path) will see a silent fallback to `en-US`.

### Confirmation

- A unit test asserts that `LocaleResolverService` returns `Locale("en-US")` when the stored
  identifier is `"en-US@calendar=buddhist;numbers=arab"`.
- A unit test asserts that `LocaleResolverService` returns `Locale("en-US")` when the stored
  identifier is `"../../etc/locale"`.
- A unit test asserts that `LocaleResolverService` returns `Locale("en-US")` when the stored
  identifier is `""` (empty string).
- A unit test asserts that `LocaleResolverService` returns `Locale("pt-BR")` when the stored
  identifier is `"pt-BR"` and `pt-BR` is present in the bundle's `localizations`.
- A unit test asserts that `LocaleResolverService` returns `Locale("en-US")` when the stored
  identifier is `"zh-Hans-CN"` (three components; not matched by the two-component constraint above
  — the schema allows only primary + region/ext + optional script, not all three together as
  distinct subtags at this length).
- `cue vet ./docs/arch/contexts/app_shell/schemas/` passes cleanly on the updated
  `#LocalePreference` schema.

## More information

- ADR-0033 — Internationalisation strategy; this ADR narrows the locale identifier constraint within
  that strategy.
- `contexts/app_shell/schemas/locale_preference.cue` — CUE schema updated by this ADR.
- `contexts/app_shell/features/locale-selection.feature` — the acceptance scenario for locale
  selection must be extended with a scenario covering the ICU keyword rejection.
- IETF BCP 47 — Tags for Identifying Languages (https://www.rfc-editor.org/rfc/rfc5646).
- Unicode CLDR locale identifiers specification —
  https://cldr.unicode.org/development/core-specification.
