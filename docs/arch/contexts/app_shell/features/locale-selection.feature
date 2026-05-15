# DDD role: BehaviouralSpecification
# DDD Role: ValueObject (#LocalePreference), DomainService (LocaleResolverService), Port (TranslationCatalogPort)
# Context: app_shell
# Related ADRs: ADR-0033 (internationalisation and multi-language support)
Feature: Locale selection and resolution

  Background:
    Given K8sManager is running on macOS 14 or later
    And the i18n_manifest.cue registry is loaded with baseline locales en, pt-BR, and es-ES
    And the app_shell/locale_preference key in local_persistence is absent (no prior operator override)

  Scenario: Application respects Locale.preferredLanguages on first launch
    Given the macOS system preferred language is "pt-BR"
    And no locale override is stored in local_persistence
    When K8sManager launches for the first time
    Then the active locale resolves to "pt-BR"
    And all UI labels, button titles, and section headers are rendered in Brazilian Portuguese
    And the Settings > Language picker shows "Português (Brasil)" as the selected item
    And no warning banner is displayed because pt-BR is a baseline locale with 100% coverage

  Scenario: Operator forces locale "pt-BR" via Settings > Language and preference persists
    Given the macOS system preferred language is "en-US"
    And the operator opens Settings > Language
    When the operator selects "Português (Brasil)" from the locale picker
    Then the LocaleResolverService updates the active locale to "pt-BR" immediately
    And the UI reloads in Brazilian Portuguese within 200 milliseconds
    And the locale preference is persisted to local_persistence under "app_shell/locale_preference" with localeIdentifier "pt-BR" and followSystem false
    And on the next application launch the active locale is "pt-BR" regardless of the system preferred language

  Scenario: Changing active locale reloads the UI within 200 milliseconds without restart
    Given the active locale is "en-US"
    And the main window is displaying the resource browser with visible labels
    When the operator changes the locale to "es-ES" in Settings > Language
    Then all visible UI labels transition to Spanish within 200 milliseconds
    And no application restart dialog is shown
    And the window title, sidebar section headers, and toolbar items are rendered in Spanish
    And the focus position in the main window is preserved after the locale change

  Scenario: Selecting an extension locale with incomplete coverage shows a warning and falls back for missing keys
    Given the extension locale "fr-FR" has translationCoverage 0.0 and status "incomplete" in i18n_manifest.cue
    And the operator selects "Français" in Settings > Language
    When the locale change is applied
    Then a warning banner is shown in the Settings > Language pane reading "This translation is incomplete. Missing strings will appear in English."
    And UI keys that have a French translation are rendered in French
    And UI keys that have no French translation are rendered in their en-US source string
    And no key identifier (e.g. "resource_browser.detail.yaml_editor.apply_button.label") is ever shown to the operator

  Scenario: Date and time formatting follows the active locale
    Given the active locale is "pt-BR"
    And dateStyle is "short" in the operator's #LocalePreference
    And a cluster resource was created at 2026-05-15T14:30:00Z
    When the operator views the resource's creation date in the detail pane
    Then the displayed date is "15/05/2026"
    And the displayed time uses the pt-BR short time format

  Scenario: Application restart restores the operator's persisted locale without prompting
    Given the operator previously selected locale "es-ES" and it is stored in local_persistence with followSystem false
    When K8sManager is quit and relaunched
    Then the active locale on launch is "es-ES"
    And no locale picker dialog or confirmation is shown
    And the main window is immediately rendered in Spanish

