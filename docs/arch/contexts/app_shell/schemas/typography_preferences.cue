// DDD role: ValueObject
package app_shell

// #TypographyPreferences captures the operator-configurable knobs
// that govern text rendering across the app shell. This value object
// is persisted in the local_persistence bounded context under the key
// "app_shell/typography_preferences" alongside ThemePreference.
//
// The preferences drive the ResolvedTextStyle read model, which is
// computed by TypographyService (a DomainService in app_shell) and
// injected into the SwiftUI environment at application launch. Views
// read resolved styles from the environment and never compute
// font properties directly.
#TypographyPreferences: {
	// uiScale applies a uniform size multiplier to all Font.system
	// calls in the content list and detail pane. The multiplier is
	// applied additively on top of Dynamic Type scaling when
	// useSystemDynamicType is true.
	//
	// "small"  — multiplier 0.875. For operators on smaller displays
	//            who prefer denser information layout.
	// "medium" — multiplier 1.0. System default.
	// "large"  — multiplier 1.125. For operators who prefer larger
	//            text without enabling system-wide accessibility scaling.
	uiScale: "small" | "medium" | "large" | *"medium"

	// monoFontFamily selects the typeface used in YAML editor, log
	// viewer, and terminal panels. The value is the PostScript family
	// name as registered in Font Book. The application validates the
	// family at launch; an unrecognised name silently falls back to
	// "SF Mono".
	//
	// Permitted values (operator cannot enter arbitrary names):
	//   "SF Mono"         — system default; always available.
	//   "JetBrains Mono"  — requires manual installation.
	//   "Berkeley Mono"   — requires license + installation.
	//   "IBM Plex Mono"   — requires manual installation.
	monoFontFamily: string | *"SF Mono"

	// monoBaseSizePoints is the base point size for mono text before
	// the uiScale multiplier is applied. Valid range: 10–16 pt.
	// 12 pt is the Apple-recommended minimum for comfortable code
	// reading at default display scaling.
	monoBaseSizePoints: int & >=10 & <=16 | *12

	// useSystemDynamicType enables Dynamic Type scaling. When true,
	// Font.system(textStyle:) calls scale with the operator's
	// accessibility font size preference from System Settings. When
	// false, font sizes are fixed to the design token values and the
	// uiScale multiplier.
	//
	// Disabling Dynamic Type is an advanced operator preference and
	// is exposed behind a disclosure group in Settings.
	useSystemDynamicType: bool | *true
}

// #TextStyleRole enumerates the semantic roles that map to font
// specifications. Each role corresponds to a SwiftUI Font.TextStyle
// or a fixed-size specification in the design-token table.
//
// The role set is closed (enum-like in CUE). Adding a new role
// requires a schema update and a corresponding entry in the
// ResolvedTextStyle lookup table.
#TextStyleRole:
	"displayLarge" |
	"display" |
	"headline" |
	"body" |
	"subheadline" |
	"callout" |
	"footnote" |
	"caption" |
	"mono"

// #ResolvedTextStyle is a read model computed by TypographyService.
// It is not persisted; it is recomputed from #TypographyPreferences
// on launch and on any preference change. Views receive instances
// through the SwiftUI Environment.
//
// Domain role: ReadModel (auxiliary to app_shell).
#ResolvedTextStyle: {
	// role identifies which logical text style this record represents.
	role!: #TextStyleRole

	// family is the resolved PostScript family name. For all non-mono
	// roles this is always "SF Pro Display" (role displayLarge) or
	// "SF Pro Text" (all other roles). For role "mono" this is the
	// operator-selected monoFontFamily.
	family!: string

	// sizePoints is the resolved point size after applying the uiScale
	// multiplier. For Dynamic Type roles this is the base size before
	// Dynamic Type scaling; the SwiftUI runtime applies Dynamic Type
	// scaling on top.
	sizePoints!: number & >0

	// weight is the CSS-compatible weight name. Maps to SwiftUI
	// Font.Weight values (ultraLight, thin, light, regular, medium,
	// semibold, bold, heavy, black).
	weight!: string

	// lineSpacing is the additional line spacing in points added on top
	// of the system default for the font size. Positive values increase
	// leading; zero means system default.
	lineSpacing!: number & >=0
}

// #TextStyleTable is the reference lookup used by TypographyService
// to build the resolved style set for a given set of preferences.
// This table encodes the design decisions from ADR-0021.
//
// The values below are for uiScale "medium" (multiplier 1.0) and
// monoBaseSizePoints 12. TypographyService scales sizePoints by the
// uiScale multiplier before constructing ResolvedTextStyle records.
#TextStyleTable: {
	entries: [
		{role: "displayLarge", family: "SF Pro Display", sizePoints: 34, weight: "bold", lineSpacing: 0},
		{role: "display", family: "SF Pro Display", sizePoints: 28, weight: "semibold", lineSpacing: 0},
		{role: "headline", family: "SF Pro Display", sizePoints: 20, weight: "semibold", lineSpacing: 0},
		{role: "body", family: "SF Pro Text", sizePoints: 15, weight: "regular", lineSpacing: 2},
		{role: "subheadline", family: "SF Pro Text", sizePoints: 13, weight: "semibold", lineSpacing: 1},
		{role: "callout", family: "SF Pro Text", sizePoints: 13, weight: "regular", lineSpacing: 1},
		{role: "footnote", family: "SF Pro Text", sizePoints: 11, weight: "regular", lineSpacing: 1},
		{role: "caption", family: "SF Pro Text", sizePoints: 10, weight: "regular", lineSpacing: 0},
		{role: "mono", family: "SF Mono", sizePoints: 12, weight: "regular", lineSpacing: 2},
	]
}
