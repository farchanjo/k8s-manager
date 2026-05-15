# DDD role: BehaviouralSpecification
# DDD Role: DomainService (LocaleResolverService, DateFormatterService), ValueObject (#LocalePreference)
# Context: app_shell
# Related ADRs: ADR-0033 (internationalisation and multi-language support)
Feature: Pluralization and locale-aware number and date formatting

  Background:
    Given K8sManager is running on macOS 14 or later
    And all localisation keys for en-US, pt-BR, and es-ES are fully translated in the .xcstrings bundle
    And the operator has not overridden timezone (timezone is "system", resolved to UTC for tests)

  Scenario: Pod count uses singular form in English for exactly one pod
    Given the active locale is "en-US"
    And the resource browser is displaying a namespace with exactly 1 running pod
    When the pod count label is rendered in the content list summary
    Then the displayed text is "1 pod"
    And the plural form "pods" is not used

  Scenario: Pod count uses plural form in English for two or more pods
    Given the active locale is "en-US"
    And the resource browser is displaying a namespace with 5 running pods
    When the pod count label is rendered in the content list summary
    Then the displayed text is "5 pods"
    And the singular form "pod" without the trailing "s" is not used

  Scenario: Pod count uses correct plural forms in Spanish
    Given the active locale is "es-ES"
    And the resource browser is displaying a namespace with 1 running pod
    When the pod count label is rendered in the content list summary
    Then the displayed text uses the Spanish singular form for pod count
    And when the namespace contains 3 running pods the displayed text uses the Spanish plural form for pod count

  Scenario: Date short style renders in pt-BR format
    Given the active locale is "pt-BR"
    And the operator's #LocalePreference has dateStyle "short"
    And a Kubernetes resource was created at the instant corresponding to 2026-05-15 (UTC)
    When the creation date is displayed in the resource detail pane
    Then the displayed date is "15/05/2026"

  Scenario: Date short style renders in en-US format
    Given the active locale is "en-US"
    And the operator's #LocalePreference has dateStyle "short"
    And a Kubernetes resource was created at the instant corresponding to 2026-05-15 (UTC)
    When the creation date is displayed in the resource detail pane
    Then the displayed date is "5/15/26"

  Scenario: Number formatting uses locale-appropriate decimal and grouping separators
    Given the operator's #LocalePreference has numberFormat "locale_default"
    When a metric value of 1234.56 is displayed in the analytics dashboard
    Then in locale "pt-BR" the displayed value is "1.234,56" with a period as grouping separator and a comma as decimal mark
    And in locale "en-US" the displayed value is "1,234.56" with a comma as grouping separator and a period as decimal mark
    And in locale "es-ES" the displayed value is "1.234,56" with a period as grouping separator and a comma as decimal mark

