// DDD role: ValueObject
package app_shell

// #ThemePreference is the operator-configurable appearance value
// object for the app shell. It is persisted in the local_persistence
// bounded context under the key "app_shell/theme_preference" with a
// schema version field (not modelled here). All fields have defaults
// that reflect the intended out-of-box experience described in
// ADR-0021.
//
// The ThemePreferenceService (DomainService in app_shell) loads this
// value on launch, validates all fields against this schema, applies
// defaults for missing or invalid fields, and injects the resolved
// value into the SwiftUI environment as a custom EnvironmentKey.
// Views read theme values from the environment and never access
// UserDefaults directly.
#ThemePreference: {
	// colorScheme controls which appearance mode the application uses.
	//
	// "system" — follows the macOS system appearance (System Settings
	//   > Appearance). This is the default and the recommended setting
	//   for most operators.
	// "light"  — forces light appearance regardless of system setting.
	// "dark"   — forces dark appearance regardless of system setting.
	colorScheme: "system" | "light" | "dark" | *"system"

	// accentSource determines the source of the accentBrand color token
	// used throughout the UI.
	//
	// "kubernetes_brand" — uses #326CE5 (light) / #5E8FF0 (dark) as
	//   the accent color, independent of the system accent setting.
	//   This is the default: it aligns with Kubernetes community brand.
	//
	// "system_tint" — delegates accent resolution to the macOS system
	//   accent color (controlAccentColor). The operator sets this in
	//   System Settings > Appearance > Accent color.
	accentSource: "kubernetes_brand" | "system_tint" | *"kubernetes_brand"

	// uiDensity controls the vertical spacing rhythm of list rows,
	// toolbar items, and form controls across the content list and
	// detail pane.
	//
	// "compact"     — reduced padding; for operators on small displays
	//                 or with high information-density preference.
	// "comfortable" — standard padding; Apple HIG default spacing.
	// "spacious"    — increased padding; for operators who prefer more
	//                 breathing room or use touch-capable displays.
	uiDensity: "compact" | "comfortable" | "spacious" | *"comfortable"

	// sidebarDensity controls the row height of navigation items in
	// the sidebar column independently of uiDensity.
	//
	// "compact" — 28 pt row height.
	// "regular" — 36 pt row height (macOS default for sidebar lists).
	sidebarDensity: "compact" | "regular" | *"regular"

	// reduceMotion disables all non-essential animations when true.
	// The application also observes the system accessibilityReduceMotion
	// preference; this field allows the operator to opt into reduced
	// motion independently of the system accessibility flag.
	//
	// When either this field or accessibilityReduceMotion is true, all
	// transitions degrade to instant (withAnimation(nil) {}). Status
	// badge updates are never animated regardless of this setting.
	reduceMotion: bool | *false

	// liquidGlassEnabled controls whether the Liquid Glass visual
	// treatment (glassEffect() modifier, macOS 26+) is applied to
	// eligible surfaces.
	//
	// The default is true on macOS 26 and above and false on macOS 14
	// and 15. On macOS 14/15 this field is silently ignored and the
	// setting is hidden in the Appearance preferences pane (the
	// glassEffect() API is unavailable at those deployment targets).
	//
	// When false on macOS 26+, eligible surfaces fall back to their
	// standard material treatment (as defined in #MaterialTokens).
	liquidGlassEnabled: bool | *false
}

// #ThemePreferenceV1 is the versioned alias for the first stable
// schema. The persistence layer stores this version tag alongside
// the serialised value. Future breaking changes produce
// #ThemePreferenceV2 and a migration transform; the domain service
// reads the version tag and applies the appropriate migration.
#ThemePreferenceV1: #ThemePreference & {
	_schemaVersion: "v1"
}
