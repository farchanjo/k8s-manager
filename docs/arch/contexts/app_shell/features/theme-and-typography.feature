# DDD role: Feature
# Bounded context: app_shell
Feature: Theme preference and typography configuration

  As an operator on macOS
  I want to control the visual appearance and typography of K8sManager
  So that the application fits my display environment and cognitive preferences

  Background:
    Given the application is installed as a Developer ID signed bundle
    And the operator has completed at least one successful launch
    And the local persistence store is available and readable

  Scenario: Application respects the macOS system color scheme by default
    Given no theme preference has been saved
    And the macOS system appearance is set to "Dark Mode"
    When the operator launches the application
    Then the application renders in dark appearance
    And the accentBrand color resolves to "#5E8FF0"
    And the surfaceBackground resolves to "#1E1E1E"

  Scenario: Force light appearance ignores system dark mode
    Given the macOS system appearance is set to "Dark Mode"
    And the operator has saved colorScheme as "light" in theme preferences
    When the operator launches the application
    Then the application renders in light appearance
    And the accentBrand color resolves to "#326CE5"
    And no dark-mode surface colors are visible in the main window

  Scenario: Force dark appearance ignores system light mode
    Given the macOS system appearance is set to "Light Mode"
    And the operator has saved colorScheme as "dark" in theme preferences
    When the operator launches the application
    Then the application renders in dark appearance
    And the accentBrand color resolves to "#5E8FF0"

  Scenario: Toggle accent source from Kubernetes brand to system tint
    Given the application is running with accentSource set to "kubernetes_brand"
    And the macOS system accent color is "Graphite"
    When the operator changes the accentSource to "system_tint" in the Appearance settings pane
    Then the toolbar buttons and sidebar selection highlight adopt the system graphite tint
    And no "#326CE5" or "#5E8FF0" hex value is used for any interactive control accent

  Scenario: UI scale small renders content list rows at 0.875x font size
    Given the application is running with uiScale set to "medium"
    When the operator changes uiScale to "small" in the Appearance settings pane
    Then the body text in the content list measures at approximately 13 points
    And the change takes effect without relaunching the application

  Scenario: UI scale large renders content list rows at 1.125x font size
    Given the application is running with uiScale set to "medium"
    When the operator changes uiScale to "large" in the Appearance settings pane
    Then the body text in the content list measures at approximately 17 points
    And the change takes effect without relaunching the application

  Scenario: Mono font family change persists and is applied to the YAML editor
    Given the application is running with monoFontFamily set to "SF Mono"
    And the operator has "JetBrains Mono" installed in Font Book
    When the operator selects "JetBrains Mono" from the mono font picker in Appearance settings
    And the operator navigates to a resource with a YAML view
    Then the YAML editor renders text in the JetBrains Mono typeface
    And the preference is persisted to the local persistence store

  Scenario: Mono base size change re-renders YAML editor at the new size
    Given the application is running with monoBaseSizePoints set to 12
    When the operator sets monoBaseSizePoints to 14 in the Appearance settings pane
    And the operator navigates to a Pod YAML view
    Then the YAML editor text renders at 14 points
    And the change takes effect without relaunching the application

  Scenario: Reduce motion disables NavigationSplitView column transition animation
    Given the application is running with reduceMotion set to false
    When the operator enables reduceMotion in Appearance settings
    And the operator toggles the sidebar column via the View menu
    Then the sidebar column appears or disappears instantly with no transition animation
    And the status bar health badge updates remain instant regardless of the reduceMotion value
