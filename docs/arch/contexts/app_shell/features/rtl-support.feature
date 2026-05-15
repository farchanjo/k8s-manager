# DDD role: BehaviouralSpecification
# DDD Role: DomainService (LocaleResolverService), ValueObject (#LocalePreference)
# Context: app_shell
# Related ADRs: ADR-0033 (internationalisation and multi-language support), ADR-0021 (app shell design system and layout)
Feature: Right-to-left layout support

  Background:
    Given K8sManager is running on macOS 14 or later
    And the extension locales "ar" (Arabic) and "he" (Hebrew) are registered in i18n_manifest.cue with status "incomplete"
    And the main window is open and fully rendered

  Scenario: Layout direction follows the active locale for Arabic
    Given the active locale is "ar"
    When the LocaleResolverService evaluates the character direction for "ar"
    Then the SwiftUI layout environment is set to rightToLeft
    And the sidebar column renders on the right side of the NavigationSplitView
    And the content list column renders to the left of the sidebar
    And the detail pane renders on the left side of the window
    And the toolbar leading items appear on the right edge and trailing items on the left edge

  Scenario: Directional icons mirror correctly in RTL locale
    Given the active locale is "he"
    And the layout direction is rightToLeft
    When the sidebar contains navigation chevron icons and disclosure arrows
    Then SF Symbols that are designated as RTL-mirrored (chevron.right, arrow.right) render in their mirrored variant
    And non-directional symbols (circle, square, cross) are not mirrored
    And the Kubernetes custom symbols (k8s.pod, k8s.deployment, etc.) are not mirrored as they are non-directional glyphs

  Scenario: YAML editor preserves left-to-right text direction regardless of active locale
    Given the active locale is "ar" and the layout direction is rightToLeft
    And the operator opens a Kubernetes resource in the YAML editor
    When the YAML editor view is rendered
    Then the text direction within the editor is leftToRight
    And YAML key-value pairs are rendered left-to-right
    And the line gutter appears on the left side of the editor content regardless of RTL locale
    And cursor navigation within the editor follows LTR text order

  Scenario: Sidebar and detail pane invert column positions in RTL locale
    Given the active locale is "ar" and the layout direction is rightToLeft
    And the NavigationSplitView is in its default three-column layout
    When the main window is rendered
    Then the sidebar (context list) column is on the right side of the window
    And the content list column is in the centre
    And the detail pane column is on the left side of the window
    And switching back to an LTR locale (e.g. "en-US") restores the sidebar to the left within 200 milliseconds

