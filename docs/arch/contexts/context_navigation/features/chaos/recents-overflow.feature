# DDD role: ChaosScenario
# Bounded context: context_navigation
# References: ADR-0005, ADR-0023, ADR-0026
# CUE schema: contexts/context_navigation/schemas/recent_context.cue

Feature: Recents list overflow — 1000 visits in one session triggers eviction policy
  As an operator running automation or stress-testing many cluster contexts
  I want the recents list to remain bounded and performant regardless of visit volume
  So that an unusually high number of context switches does not degrade the navigator

  Background:
    Given the operator has 1000 distinct cluster contexts in their kubeconfig
    And the ContextNavigationState recents window is configured with a maximum of 5 entries (default)
    And the operator has pinned "prod-us-east-1" and "prod-eu-west-1"

  @chaos @eviction
  Scenario: 1000 sequential context visits trigger recents eviction policy
    When the operator visits each of the 1000 cluster contexts once in rapid succession
    Then the ContextNavigationState maintains at most 5 entries in the recents list at all times
    And after all 1000 visits the recents list contains exactly the 5 most recently visited contexts
    And each evicted entry is removed from the recents list without error or memory leak
    And no visit event causes a linear scan of the entire 1000-entry visit log

  @chaos @eviction
  Scenario: Pinned items always survive recents overflow eviction
    Given the operator visits 1000 contexts while "prod-us-east-1" is pinned
    When the eviction policy runs after each visit
    Then "prod-us-east-1" is never evicted from the pinned section regardless of visit volume
    And "prod-eu-west-1" remains pinned throughout all 1000 visits
    And the recents list is evicted normally without touching the pinned section
    And the total navigator item count never exceeds 7 (5 recents + 2 pinned)

  @chaos @persistence
  Scenario: Recents list written to storage.sqlite3 remains consistent after bulk evictions
    Given the operator has visited 1000 contexts producing 995 eviction events
    When the application quits and relaunches
    Then the recents list loaded from "storage.sqlite3" contains exactly the 5 entries
         that were most recently visited before the quit
    And no stale evicted entries are present in "storage.sqlite3"
    And the pinned entries for "prod-us-east-1" and "prod-eu-west-1" are preserved intact
