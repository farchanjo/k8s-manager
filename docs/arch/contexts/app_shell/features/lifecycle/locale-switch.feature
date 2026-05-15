# DDD role: BehaviouralSpecification
# Bounded context: app_shell
# References: ADR-0021, ADR-0033

Feature: Runtime locale switch without app restart
  As an operator
  I want to change the application locale at runtime and see all UI strings update immediately
  So that I can use K8sManager in my preferred language without restarting

  Background:
    Given the application is running with locale "en" (English)
    And all UI strings are bound via @Observable locale state

  @happy @lifecycle
  Scenario: Locale switch from en to pt-BR rebinds all UI strings without restart
    When the operator selects "pt-BR" in Settings → Language
    And the locale preference is written to "storage.sqlite3"
    Then the LocalePreference @Observable value updates to "pt-BR"
    And all SwiftUI views that observe locale strings re-render with Portuguese translations
    And no app restart is required
    And plural forms (e.g., "1 namespace" vs "2 namespaces") are correctly rendered in pt-BR rules

  @happy @lifecycle
  Scenario: Locale switch persists across app restarts
    Given the operator changed the locale to "pt-BR" and closed the app
    When the application launches
    Then "storage.sqlite3" contains locale preference "pt-BR"
    And the application starts in pt-BR locale from the first rendered frame
    And no flash of English content is shown before switching

  @failure @lifecycle
  Scenario: Unsupported locale falls back to en
    When the operator attempts to set an unsupported locale "tlh" (Klingon)
    Then the application rejects the locale and keeps the current locale unchanged
    And a validation message is shown: "Language 'tlh' is not supported — currently supported: en, pt-BR, es, de, fr, ja, zh-Hans"

  @happy @lifecycle
  Scenario: RTL locale switch also changes layout direction
    When the operator switches to an RTL locale (e.g., "ar")
    Then the application's SwiftUI layout environment reflects the RTL direction
    And navigation sidebars and text fields are mirrored appropriately
    And no restart is required for the layout direction change to take effect
