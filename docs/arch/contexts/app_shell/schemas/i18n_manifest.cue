// DDD role: ValueObject
package app_shell

// #I18nManifest is the top-level internationalisation registry.
// It declares the source locale, the baseline locales shipped and
// maintained by the core team, and the extension locales contributed
// and maintained by the community.
//
// This schema is the governance contract for ADR-0033. Adding a new
// extension locale requires:
//   1. A PR updating the .xcstrings files with coverage >= 0.75.
//   2. A new #SupportedLocale entry in extensionLocales below.
//   3. `cue vet ./docs/arch/contexts/app_shell/schemas/` passing cleanly.
//
// Removing a locale is not permitted; coverage may drop to zero and
// status may move to "incomplete", but the identifier is never deleted.
#I18nManifest: {
	// sourceLocale is the language in which all translatable keys and
	// their source values are authored. Constant. Never changes.
	sourceLocale: "en-US"

	// baselineLocales lists the BCP 47 identifiers of the locales that
	// are shipped with the application and maintained by the core team.
	// Coverage for baseline locales must be 1.0 (100%) at every release.
	baselineLocales: ["en", "pt-BR", "es-ES"]

	// extensionLocales is the community-maintained locale registry.
	// Entries are ordered by date added (addedInVersion, then identifier).
	// New entries are always appended; existing entries are never moved.
	extensionLocales: [...#SupportedLocale]
}

// i18nManifest is the canonical singleton instance of #I18nManifest.
// It is consumed by the CUE lint gate and by the Settings → Language
// picker at build time to enumerate available locales.
i18nManifest: #I18nManifest & {
	sourceLocale: "en-US"
	baselineLocales: ["en", "pt-BR", "es-ES"]
	extensionLocales: [
		{
			identifier:          "pt-PT"
			displayName:         "Português (Portugal)"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			identifier:          "es-MX"
			displayName:         "Español (México)"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			identifier:          "es-AR"
			displayName:         "Español (Argentina)"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			identifier:          "fr-FR"
			displayName:         "Français"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			identifier:          "de-DE"
			displayName:         "Deutsch"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			identifier:          "it-IT"
			displayName:         "Italiano"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			identifier:          "nl-NL"
			displayName:         "Nederlands"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			identifier:          "pl-PL"
			displayName:         "Polski"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			identifier:          "ru-RU"
			displayName:         "Русский"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			identifier:          "ja-JP"
			displayName:         "日本語"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			identifier:          "ko-KR"
			displayName:         "한국어"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			identifier:          "zh-Hans"
			displayName:         "中文（简体）"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			identifier:          "zh-Hant"
			displayName:         "中文（繁體）"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			// ar is also an RTL layout test target during development.
			// When translationCoverage reaches 0.75 a community maintainer
			// should update status to "beta".
			identifier:          "ar"
			displayName:         "العربية"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
		{
			// he is also an RTL layout test target during development.
			identifier:          "he"
			displayName:         "עברית"
			translationCoverage: 0.0
			maintainer:          "(open)"
			addedInVersion:      "1.0.0"
			status:              "incomplete"
		},
	]
}

// #TranslatableKey describes a single localisation key used across
// the application's .xcstrings files. This schema is used for
// documentation and lint tooling; it is not loaded at runtime.
//
// Translator tooling may read the CUE-exported JSON of declared
// #TranslatableKey instances to produce a translation brief.
#TranslatableKey: {
	// keyPath is the dot-separated localisation key following the
	// convention: <bc>.<screen>.<element>.<purpose>
	// e.g. "resource_browser.detail.yaml_editor.apply_button.label"
	keyPath: string

	// englishSource is the authoritative en-US string for this key.
	// Translators use this as the source text.
	englishSource: string

	// contextHint is an optional free-text note for translators
	// explaining where this string appears, what surrounding UI
	// elements look like, and any constraints (character limit, tone).
	contextHint?: string

	// pluralized indicates whether this key has plural variants.
	// When true, the plurals field must be present.
	pluralized: bool | *false

	// plurals maps CLDR plural category names to the English template
	// string for that category. Used when pluralized is true.
	//
	// Standard CLDR categories: "zero", "one", "two", "few", "many", "other".
	// English uses only "one" and "other"; Spanish uses "one" and "other";
	// Arabic uses all six.
	//
	// The value strings use %d as the integer placeholder, following
	// Foundation's stringsdict convention.
	plurals?: {
		[CLDRRule=string]: string
	}
}
