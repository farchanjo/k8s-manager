# DDD role: BehaviouralSpecification
# DDD Role: AggregateRoot (NavigationHistoryActor), ValueObject (NavigationEntry)
# Context: app_shell
# Related ADRs: ADR-0065 (Navigation history stack), ADR-0023 (Command palette and shortcuts), ADR-0050 (Resource navigation taxonomy)
Feature: Navigation history back and forward

  Background:
    Given a cluster session is active with cluster-id "cluster-a"
    And the navigation history deque is empty
    And the operator has no unsaved changes in the YAML editor

  Scenario: Back arrow restores previous resource selection
    Given the operator navigates to the Deployments list in namespace "default"
    And the operator selects the row for deployment "api-server"
    And the detail drawer opens at the "properties" section for "api-server"
    When the operator navigates to the Pods list in namespace "default"
    And the operator selects the row for pod "api-server-7d9f8c-xkqpz"
    Then the navigation history deque contains 3 entries
    When the operator clicks the back arrow button
    Then the active list view switches to the Deployments list in namespace "default"
    And the row for deployment "api-server" is selected
    And the detail drawer is open at the "properties" section
    And the viewport scroll offset is restored to the position recorded in the history entry
    And the back arrow button remains enabled
    And the forward arrow button becomes enabled

  Scenario: Forward arrow re-applies the next history entry
    Given the operator has navigated to the Deployments list and then to the Pods list
    And the navigation history deque contains 2 entries with cursor at index 1
    When the operator clicks the back arrow button
    Then the cursor moves to index 0 and the Deployments list is restored
    When the operator clicks the forward arrow button
    Then the cursor moves to index 1 and the Pods list is restored
    And the forward arrow button becomes disabled
    And the back arrow button remains enabled

  Scenario: Back across tabs switches the active tab
    Given a tab "tab-deployments" is open for the Deployments list in cluster "cluster-a" namespace "default"
    And a tab "tab-pods" is open for the Pods list in cluster "cluster-a" namespace "default"
    And the operator selects deployment "nginx" in tab "tab-deployments"
    And the active tab switches to "tab-pods"
    And the operator selects pod "nginx-66b4c67d-p9s4k" in tab "tab-pods"
    When the operator clicks the back arrow button
    Then OpenTabsActor receives a focusTab command for tab-id "tab-deployments"
    And the active tab becomes "tab-deployments"
    And the row for deployment "nginx" is re-selected in the Deployments list
    And the detail drawer is restored to the anchor recorded in the history entry for that selection

  Scenario: Keyboard ⌘[ and ⌘] dispatch back and forward
    Given the operator has navigated through 3 resource selections
    And the navigation history deque contains 3 entries with cursor at index 2
    When the operator presses "⌘["
    Then NavigationHistoryActor.back() is invoked
    And the cursor moves to index 1
    And the view state matches the entry at index 1
    When the operator presses "⌘["
    Then NavigationHistoryActor.back() is invoked
    And the cursor moves to index 0
    And the back arrow button becomes disabled
    When the operator presses "⌘]"
    Then NavigationHistoryActor.forward() is invoked
    And the cursor moves to index 1
    And the forward arrow button remains enabled

  Scenario: History persists across application launch up to 50 entries
    Given the operator has performed 60 resource navigations during a session
    And the navigation history deque contains 60 entries
    When the application writes history to disk before terminating
    Then the persisted file at "workspace/navigation-history.json" contains exactly 50 entries
    And the 50 entries correspond to the 50 most-recent navigation entries
    When the application cold-launches and restores the persisted history
    Then NavigationHistoryActor contains 50 entries
    And the cursor is positioned at index 49 (the most recent entry)
    And the back arrow button is enabled
    And the forward arrow button is disabled
