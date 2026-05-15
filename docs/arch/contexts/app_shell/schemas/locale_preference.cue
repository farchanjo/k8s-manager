// DDD role: ValueObject
package app_shell

// #LocalePreference is the operator-configurable locale and
// formatting value object for the app shell. It is persisted in the
// local_persistence bounded context under the key
// "app_shell/locale_preference". The LocaleResolverService (DomainService
// in app_shell) loads this value on launch, validates all fields against
// this schema, applies defaults for missing or invalid fields, and
// injects the resolved Locale into the SwiftUI environment.
//
// Timezone is stored here as a convenience co-location with locale,
// but is treated as an orthogonal concern: the operator may set a
// Brazilian Portuguese locale with UTC timezone. The two fields never
// imply each other.
//
// See ADR-0033 for the full internationalisation strategy.
#LocalePreference: {
	// localeIdentifier is a BCP 47 / Apple locale string identifying
	// the display language and region for UI strings, date formatting,
	// number formatting, and layout direction resolution.
	//
	// Examples: "en-US", "pt-BR", "es-ES", "ja-JP", "ar".
	//
	// The value must match an entry in the application bundle's list of
	// supported locales (as declared in #I18nManifest.baselineLocales or
	// #I18nManifest.extensionLocales). When absent or unrecognised, the
	// LocaleResolverService falls back to Locale.preferredLanguages[0]
	// and ultimately to "en-US".
	localeIdentifier: string

	// followSystem controls whether the application tracks the macOS
	// system locale preference automatically.
	//
	// When true, localeIdentifier is ignored and the application always
	// uses Locale.preferredLanguages[0]. Operator changes to the system
	// language in macOS System Settings propagate immediately.
	//
	// When false, localeIdentifier is used as the explicit override.
	// This is the setting the operator makes in Settings → Language.
	followSystem: bool | *true

	// dateStyle controls the date format length used in all date-only
	// display contexts (e.g. resource creation dates, audit log dates).
	//
	// "short"  — e.g. 5/15/26 (en-US), 15/05/2026 (pt-BR).
	// "medium" — e.g. May 15, 2026 (en-US), 15 de mai. de 2026 (pt-BR).
	// "long"   — e.g. May 15, 2026 (en-US), 15 de maio de 2026 (pt-BR).
	// "full"   — e.g. Friday, May 15, 2026 (en-US).
	//
	// Formatting is always performed by Foundation.DateFormatter with
	// the resolved Locale; no format strings are hardcoded.
	dateStyle: "short" | "medium" | "long" | "full" | *"medium"

	// timeStyle controls the time format length used in all time display
	// contexts (e.g. metric timestamps, log line times, audit log times).
	//
	// "short"  — e.g. 3:30 PM (en-US), 15:30 (pt-BR).
	// "medium" — e.g. 3:30:45 PM (en-US).
	// "long"   — includes timezone abbreviation (e.g. 3:30:45 PM PDT).
	//
	// Formatting is always performed by Foundation.DateFormatter with
	// the resolved Locale.
	timeStyle: "short" | "medium" | "long" | *"short"

	// timezone is a TZ database identifier (IANA timezone) or the
	// sentinel value "system".
	//
	// "system"           — uses TimeZone.current; follows macOS system
	//                       timezone setting. This is the default.
	// TZ identifier      — a valid IANA timezone string such as
	//                       "America/Sao_Paulo", "Europe/Madrid", "UTC".
	//
	// The timezone setting is entirely orthogonal to localeIdentifier:
	// an operator may use "pt-BR" display language with "UTC" timezone.
	//
	// Internal timestamps are always stored in RFC 3339 / ISO 8601. The
	// timezone value is applied only at the presentation layer by the
	// DateFormatterService.
	timezone: string | *"system"

	// numberFormat controls the numeric formatting style for standalone
	// numbers (e.g. resource counts, metric values) that are not already
	// handled by Locale.current's default formatter.
	//
	// "locale_default" — delegates entirely to NumberFormatter with the
	//                    resolved Locale, producing locale-appropriate
	//                    grouping separators and decimal marks.
	// "decimal"        — forces US-style decimal formatting regardless of
	//                    locale. Intended for machine-readable output
	//                    contexts (e.g. clipboard copy of a metric value).
	//
	// The default is "locale_default" to honour operator locale expectations.
	numberFormat: "decimal" | "locale_default" | *"locale_default"

	// layoutDirection controls the base UI layout direction. In almost all
	// cases this should remain "auto" so that SwiftUI resolves the correct
	// direction from the active Locale's character direction.
	//
	// "ltr"  — forces left-to-right regardless of locale.
	// "rtl"  — forces right-to-left regardless of locale.
	// "auto" — resolved from Locale.Characterization.characterDirection
	//          of the active localeIdentifier. Default.
	//
	// Note: code editors (YAML, JSON, terminal) are always LTR regardless
	// of this setting; they apply an independent override.
	layoutDirection: "ltr" | "rtl" | "auto" | *"auto"

	// pluralizationRule is an optional BCP 47 locale string that overrides
	// the locale used for CLDR plural category selection. When absent,
	// the pluralization locale is the same as localeIdentifier.
	//
	// This field exists to support edge cases where an operator uses a
	// regional locale (e.g. "es-MX") that is not yet in the extension
	// locale list but whose plural rules match a supported locale (e.g.
	// "es-ES"). In normal use this field should remain unset.
	pluralizationRule?: string
}

// #LocalePreferenceV1 is the versioned alias for the first stable
// persistence schema. The persistence layer stores the version tag
// alongside the serialised value. Future breaking changes produce
// #LocalePreferenceV2 and a migration transform.
#LocalePreferenceV1: #LocalePreference & {
	_schemaVersion: "v1"
}

// #LocaleManifest is the registry of all locales the application
// is aware of. It is the governance contract for the community
// extension model described in ADR-0033. The canonical instance
// is declared in i18n_manifest.cue; this schema defines the shape.
#LocaleManifest: {
	// version is a monotonically increasing integer. Increment when
	// the structure of this manifest changes (field additions, removals,
	// or semantic changes to existing fields). Adding new entries to
	// extensionLocales does not require a version bump.
	version: int | *1

	// supportedLocales is the full ordered list of locales known to
	// the application, combining baseline and extension locales.
	// The first entry is always the source locale (en-US).
	supportedLocales: [...#SupportedLocale]
}

// #SupportedLocale is one entry in the locale registry.
#SupportedLocale: {
	// identifier is a BCP 47 locale string as recognised by Apple's
	// Locale API (e.g. "en-US", "pt-BR", "es-ES", "zh-Hans").
	identifier: string

	// displayName is the locale's own-script name for itself, used in
	// the Settings → Language picker. Must be written in the target
	// locale's script (e.g. "Português (Brasil)" not "Brazilian Portuguese").
	displayName: string

	// translationCoverage is the fraction of all translatable keys that
	// have a translation in this locale. Range [0.0, 1.0]. A value of
	// 1.0 means every key is translated. Used to display coverage
	// badges in the Settings → Language picker and to determine
	// whether to show a fallback warning banner.
	translationCoverage: >=0 & <=1

	// maintainer is the GitHub handle (e.g. "@username") of the
	// individual or team responsible for keeping this locale up to date.
	// For baseline locales (en, pt-BR, es-ES) this is "@archanjo-team".
	maintainer: string

	// addedInVersion is the application release version string at which
	// this locale was first included (e.g. "1.0.0", "1.2.0-beta").
	addedInVersion: string

	// status indicates the current quality level of this locale.
	//
	// "stable"     — translation coverage >= 95%; actively maintained;
	//                no warning shown to operator.
	// "beta"       — translation coverage >= 75%; community-maintained;
	//                a soft "community translation" badge is shown.
	// "incomplete" — translation coverage < 75%; missing keys fall back
	//                to en-US; a warning banner is shown when this locale
	//                is active in the UI.
	status: "stable" | "beta" | "incomplete"
}
