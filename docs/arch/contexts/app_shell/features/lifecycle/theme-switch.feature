# DDD role: BehaviouralSpecification
# Bounded context: app_shell
# References: ADR-0021, ADR-0034

Feature: System theme change re-renders app with new color tokens within 200 ms
  As an operator
  I want K8sManager to immediately follow macOS system theme changes
  So that the application looks correct in dark mode and light mode without any intervention

  Background:
    Given the application is running in light mode
    And all SwiftUI views are bound to the design-system color token set

  @happy @lifecycle
  Scenario: System switches to dark mode — all color tokens rebind within 200 milliseconds
    When macOS switches to dark mode (NSAppearance change notification)
    Then the ThemePreference @Observable value updates to "dark"
    And all color tokens from the design system re-evaluate to their dark-mode values
    And all SwiftUI views re-render with the dark color token set
    And the entire re-render completes within 200 milliseconds from the appearance notification

  @happy @lifecycle
  Scenario: System switches back to light mode — re-render also within 200 milliseconds
    Given the application is in dark mode
    When macOS switches to light mode
    Then the ThemePreference updates to "light"
    And all views re-render with the light color token set within 200 milliseconds

  @happy @lifecycle
  Scenario: Operator-forced theme override ignores system preference
    When the operator selects "Always Dark" in Settings → Appearance
    And the preference is written to "storage.sqlite3"
    Then the ThemePreference is locked to "dark" regardless of macOS system appearance
    When macOS switches to light mode
    Then the application remains in dark mode (operator override takes precedence)

  @failure @lifecycle
  Scenario: Theme change during an active modal does not dismiss the modal
    Given a deletion confirmation modal is open
    When macOS switches to dark mode
    Then the modal re-renders with dark color tokens
    And the modal remains open (theme change is not treated as a dismiss gesture)
    And the operator can still interact with the modal normally after the theme transition
