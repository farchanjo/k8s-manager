// DDD role: ValueObject
package app_shell

// #ColorTokens defines the canonical color token set for the
// K8sManager design system. Each token declares a light-mode hex
// value and a dark-mode hex value, or a reference to a macOS system
// color (e.g., NSColor.controlAccentColor) when the semantic meaning
// requires following the system setting.
//
// All hex values use six-character lowercase notation (#rrggbb).
// Token values are resolved into a SwiftUI Color Asset Catalog at
// build time; no hardcoded hex literal appears in view source outside
// this schema and the generated catalog.
#ColorTokens: {
	// --- Brand palette ---
	// brandPrimaryLight is the Kubernetes brand accent (#326CE5,
	// Pantone 285C as documented in the Kubernetes brand guidelines).
	// Used as the default accentBrand token in light mode.
	brandPrimaryLight: string | *"#326CE5"

	// brandPrimaryDark is the dark-mode counterpart of brandPrimaryLight.
	// Chosen for contrast against dark surface backgrounds while
	// preserving hue continuity.
	brandPrimaryDark: string | *"#5E8FF0"

	// brandNavy is the deep navy used for pressed and active states in
	// light mode. Also suitable as a background tint in light-mode hero
	// areas.
	brandNavy: string | *"#0F3074"

	// brandSky is the light sky-blue used for tinted backgrounds and
	// soft highlights. Passes 3:1 against white at WCAG large-text size.
	brandSky: string | *"#9DB8E9"

	// --- Semantic surface tokens ---
	// Each semantic token is expressed as a struct with light and dark
	// hex values. The Color Asset Catalog generator reads this schema
	// and produces one .colorset per token.

	surfaceBackground: #ColorPair
	surfaceElevated:   #ColorPair
	accentBrand:       #ColorPair

	// --- Semantic text tokens ---
	textPrimary:   #ColorPair
	textSecondary: #ColorPair
	textTertiary:  #ColorPair

	// --- Status semantic tokens ---
	// These tokens communicate cluster and resource health. Each token
	// must achieve 3:1 contrast against surfaceBackground.light and
	// surfaceBackground.dark respectively.
	statusHealthy:     #ColorPair
	statusWarning:     #ColorPair
	statusError:       #ColorPair
	statusTerminating: #ColorPair
	statusUnknown:     #ColorPair

	// --- Kind accent tokens ---
	// Used for resource-kind badges and row tints in the content list.
	// Hue selection follows the K8sManager kind-to-hue mapping.
	kindAccentPod:     #ColorPair
	kindAccentDeploy:  #ColorPair
	kindAccentService: #ColorPair
	kindAccentStorage: #ColorPair
	kindAccentConfig:  #ColorPair
	kindAccentRBAC:    #ColorPair
}

// #ColorPair is the base value type for all semantic color tokens.
// It carries a light-mode value and a dark-mode value. Each value is
// either a six-character hex string or a named macOS system color
// reference. Named system color references are used only for tokens
// that must track dynamic system colors (e.g., controlAccentColor).
#ColorPair: {
	// light is the hex color value or system color reference for
	// light appearance. Format: "#rrggbb" or "system.<NSColorName>".
	light!: string

	// dark is the hex color value or system color reference for
	// dark appearance. Format: "#rrggbb" or "system.<NSColorName>".
	dark!: string
}

// Default values for the canonical K8sManager color token set.
// Views that need token values import this constraint unification.
#DefaultColorTokens: #ColorTokens & {
	surfaceBackground: {light: "#FFFFFF", dark: "#1E1E1E"}
	surfaceElevated: {light: "#F5F5F5", dark: "#2A2A2A"}
	accentBrand: {light: "#326CE5", dark: "#5E8FF0"}

	textPrimary: {light: "#111111", dark: "#F0F0F0"}
	textSecondary: {light: "#555555", dark: "#AAAAAA"}
	textTertiary: {light: "#999999", dark: "#666666"}

	statusHealthy: {light: "#1A7F37", dark: "#3FB950"}
	statusWarning: {light: "#9A6700", dark: "#D29922"}
	statusError: {light: "#CF222E", dark: "#F85149"}
	statusTerminating: {light: "#BF7B00", dark: "#E3B341"}
	statusUnknown: {light: "#656D76", dark: "#8B949E"}

	kindAccentPod: {light: "#0550AE", dark: "#2F81F7"}
	kindAccentDeploy: {light: "#3B36C3", dark: "#7C72EA"}
	kindAccentService: {light: "#0D7377", dark: "#2CB9BB"}
	kindAccentStorage: {light: "#6B32B0", dark: "#B57AE7"}
	kindAccentConfig: {light: "#7D4617", dark: "#C67D3C"}
	kindAccentRBAC: {light: "#A41D5C", dark: "#E57BB2"}
}

// #MaterialTokens declares the SwiftUI material identifiers assigned
// to each structural surface in the main window. Material values map
// directly to SwiftUI Material enum cases. These assignments are fixed
// by ADR-0021 and are not operator-configurable.
#MaterialTokens: {
	// sidebarMaterial is applied to the NavigationSplitView sidebar
	// column background. Use ".bar" on macOS 14 and ".sidebar" on
	// macOS 15+; the SwiftUI runtime selects the appropriate system
	// backing on each OS version.
	sidebarMaterial: "bar" | "sidebar" | *"sidebar"

	// contentMaterial is applied to the NavigationSplitView content
	// list column background.
	contentMaterial: "regular" | *"regular"

	// inspectorMaterial is applied to the .inspector panel background.
	inspectorMaterial: "thin" | *"thin"

	// popoverMaterial is applied to popover backgrounds. Popovers are
	// ephemeral surfaces; ultra-thin minimises visual weight.
	popoverMaterial: "ultraThin" | *"ultraThin"

	// sheetMaterial is applied to sheet presentation backgrounds.
	// Thick material reinforces the blocking nature of modal sheets.
	sheetMaterial: "thick" | *"thick"
}

// #SpacingTokens defines the discrete spacing scale used for
// padding, margins, gaps, and stack spacing in the app shell UI.
// All values are in points. The scale is taken from a 4-pt base grid,
// consistent with Apple's HIG recommendations.
#SpacingTokens: {
	// scale lists the available spacing values in ascending order.
	// Designers and engineers pick from this list only; intermediate
	// values require a new token proposal.
	scale: [4, 8, 12, 16, 24, 32]

	// Semantic aliases that map to scale entries:
	xsmall: 4  // micro gaps between icon and label
	small:  8  // intra-group padding
	medium: 12 // standard list row padding
	base:   16 // standard content area inset
	large:  24 // section vertical spacing
	xlarge: 32 // hero section top padding
}

// #RadiusTokens defines the corner-radius scale used for buttons,
// cards, and badges in the app shell UI. All values are in points.
#RadiusTokens: {
	// scale lists the available corner radii in ascending order.
	scale: [4, 8, 12]

	// Semantic aliases:
	small:  4  // tight elements such as status badges and inline tags
	medium: 8  // standard buttons, text fields, sidebar group headers
	large:  12 // cards, sheet corners, inspector panel top corners
}
