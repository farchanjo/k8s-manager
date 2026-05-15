# DDD role: BehaviouralSpecification
# DDD Role: ReadModel (accessibility preferences), ApplicationService (a11y enforcement)
# Context: app_shell
# Related ADRs: ADR-0021 (design system and contrast tokens), ADR-0023 (keyboard-only navigation, VoiceOver contract)
Feature: Accessibility compliance

  Background:
    Given K8sManager is running on macOS 14 or later
    And the main window is open with at least one cluster context loaded

  Scenario: Keyboard-only navigation reaches every interactive element
    Given no pointer device is used
    When the operator navigates using Tab, Shift-Tab, arrow keys, Return, and Escape
    Then every interactive element in the sidebar, content list, detail pane, and toolbar is reachable
    And the command palette can be opened with the Command-P shortcut from any focused element
    And activating a resource row with Return opens the detail pane without mouse interaction

  Scenario: VoiceOver announces descriptive labels for every widget
    Given VoiceOver is enabled in macOS Accessibility settings
    When VoiceOver focus traverses the main window
    Then each cluster health badge announces its cluster name and current health status
    And each resource list row announces kind, name, namespace, and status
    And the command palette result rows announce title, subtitle, and keyboard shortcut if present
    And the status bar announces cluster, namespace, sync indicator, and health summary

  Scenario: All text passes WCAG AA contrast in light appearance
    Given the system appearance is set to Light
    When the main window is rendered
    Then all text tokens defined in the design_tokens.cue color scheme achieve at least 4.5:1 contrast ratio against their background surface token in Light mode
    And status tokens achieve at least 3:1 contrast against the surface-background token in Light mode

  Scenario: All text passes WCAG AA contrast in dark appearance
    Given the system appearance is set to Dark
    When the main window is rendered
    Then all text tokens defined in the design_tokens.cue color scheme achieve at least 4.5:1 contrast ratio against their background surface token in Dark mode
    And status tokens achieve at least 3:1 contrast against the surface-background token in Dark mode

  Scenario: Reduce Motion disables all animated transitions
    Given the operator has enabled Reduce Motion in macOS Accessibility settings
    When any panel opens, closes, or transitions between disclosure layers
    Then no spring or opacity animation is played
    And the transition is immediate with no intermediate frames

  Scenario: Increased Contrast mode adjusts brand accent token
    Given the operator has enabled Increase Contrast in macOS Accessibility settings
    When the main window is rendered
    Then the brand accent color is replaced with a higher-contrast variant that meets 7:1 ratio against the surface background
    And all interactive element borders are rendered with increased opacity

  Scenario: Dynamic Type size preference is respected across text styles
    Given the operator has set a non-default font size in macOS Accessibility settings
    And useSystemDynamicType is enabled in typography preferences
    When the main window is rendered
    Then all text elements scale proportionally to the system Dynamic Type preference
    And no text is clipped or truncated due to size increase up to the accessibility extra-extra-extra large size

  Scenario: Focus ring is visible on every interactive element
    Given the keyboard is the primary input device
    When the operator tabs to or arrows onto any interactive element
    Then a visible focus ring is rendered around the element
    And the focus ring color contrasts with the surface background at a ratio of at least 3:1
    And the focus ring is not hidden by adjacent elements or clipped by scroll views

  Scenario: Pointer Accessibility large and medium cursor sizes are accommodated
    Given the operator has selected a large or medium pointer in macOS Accessibility settings
    When the operator hovers over interactive elements in the main window
    Then hit targets are at least 44 by 44 points in both axes
    And no interactive element is unreachable due to overlap with a scaled cursor
