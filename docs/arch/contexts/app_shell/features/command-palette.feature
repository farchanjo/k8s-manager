# DDD role: Feature
# Bounded context: app_shell
Feature: Command palette universal entry point

  As a Kubernetes operator on macOS
  I want a fuzzy-search command palette accessible from any screen state
  So that I can discover and execute any command within two keystrokes without reaching for the mouse

  Background:
    Given the application is running with at least one cluster connected
    And the local persistence store contains a non-empty command catalog
    And the command palette is currently closed

  Scenario: Open palette with primary shortcut
    When the operator presses Cmd-P
    Then the command palette overlay is visible
    And the text input field has keyboard focus
    And the result list shows the most recent invocations ranked by frequency times recency
    And the selected index is zero

  Scenario: Open palette with alternate shortcut
    When the operator presses Cmd-K
    Then the command palette overlay is visible
    And the text input field has keyboard focus
    And the result list shows the most recent invocations ranked by frequency times recency

  Scenario: Fuzzy search narrows results as the operator types
    Given the command palette is open with an empty query
    When the operator types "log"
    Then the result list contains an entry with title "Stream logs"
    And all visible entries have at least one token that fuzzy-matches "log"
    And the selected index resets to zero after each keystroke

  Scenario: Type-ahead preview renders for the selected entry
    Given the command palette is open with query "exec"
    And the result list contains the "exec-shell" entry at index zero
    When the operator presses the down-arrow key
    Then the type-ahead action preview updates to show the entry at index one
    And the preview includes the entry title and subtitle

  Scenario: Invoke selected command via Enter and dismiss palette
    Given the command palette is open
    And the "refresh-view" entry is at the selected index
    When the operator presses Enter
    Then the refresh action is executed
    And the command palette overlay is dismissed
    And keyboard focus returns to the element that had focus before the palette opened
    And a CommandInvocation record is prepended to the recentInvocations ring

  Scenario: Esc closes palette without executing a command
    Given the command palette is open with query "del"
    When the operator presses Escape
    Then the command palette overlay is dismissed
    And no command is executed
    And keyboard focus returns to the element that had focus before the palette opened
    And the recentInvocations ring is unchanged

  Scenario: Recent invocations ring respects the 50-entry limit
    Given the recentInvocations ring already contains 50 invocation records
    When the operator invokes any command via the palette
    Then the ring still contains exactly 50 records
    And the new invocation is the first entry in the ring
    And the oldest previous entry is evicted

  Scenario: Context-sensitive commands are hidden when no resource is focused
    Given no resource row is selected in the resource browser
    When the operator opens the command palette and types "exec"
    Then no entry with requiresContext equal to true appears in the result list
    And context-free entries matching "exec" are still shown

  Scenario: VoiceOver announces result count on query change
    Given the command palette is open
    And VoiceOver is active
    When the operator types "scale"
    Then an accessibility announcement is posted with the number of results found
    And each result row has an accessibilityLabel combining title, subtitle, and keyboard shortcut

  Scenario: Clicking outside the palette overlay closes it
    Given the command palette is open with query "deploy"
    When the operator clicks on the resource browser list outside the palette overlay
    Then the command palette overlay is dismissed
    And no command is executed
