# DDD role: BehaviouralSpecification
@adr-0031
Feature: Loading states and async resource UX
  As an operator of K8sManager
  I want clear, consistent visual feedback during data loading
  So that I always know the current state of the application and can act accordingly

  Background:
    Given the application is running on macOS 14 or later
    And the operator has at least one cluster context configured

  Scenario: Skeleton loader appears in sidebar when loading cluster list
    Given the application has just launched
    And the sidebar cluster list is in "idle" state
    When the sidebar initiates a cluster list load
    Then the sidebar transitions to "loading" state
    And skeleton placeholder rows are visible in the sidebar within 200 ms of load start
    And each placeholder row matches the height of a real cluster row
    And no real cluster names or badges are visible during skeleton state
    When the cluster list loads successfully
    Then the skeleton rows are replaced by real cluster rows
    And the sidebar state is "success"

  Scenario: Shimmer overlay appears on resource list when load takes longer than 100 ms
    Given the operator has selected a namespace with many resources
    When the resource list begins loading
    And 200 ms have elapsed since load started
    Then a shimmer overlay is visible on the resource list placeholder
    And the shimmer gradient animates diagonally from top-leading to bottom-trailing
    When the resource list finishes loading
    Then the shimmer overlay is removed
    And the resource list displays the loaded items

  Scenario: Spinner is shown for quick operations expected to complete in under 500 ms
    Given the operator opens the command palette
    When the search index is warming on first open
    Then a centered indeterminate ProgressView spinner is visible
    And no skeleton or shimmer overlay is shown
    When the search index finishes warming
    Then the spinner is replaced by the search results list

  Scenario: Empty state with action hint when a namespace has no pods
    Given the operator selects a namespace that contains no Pod resources
    When the pod list loads successfully
    Then the "AsyncResource" state is "success"
    And an empty state view is displayed showing "No pods in this namespace"
    And the empty state includes a contextual message explaining why pods may be absent
    And a "Switch namespace" action button is visible

  Scenario: Error state with retry button when pod list load fails
    Given the operator selects a namespace
    And the Kubernetes API returns a 503 error on the pod watch stream
    When the pod list transitions to "failure" state
    Then an error state view is displayed with title "Failed to load pods"
    And a "Retry" button is visible
    And a "Show details" toggle is available to expand the error message
    When the operator presses "Retry"
    Then the pod list transitions back to "loading" state
    And a skeleton loader appears after 200 ms

  Scenario: 200 ms throttle prevents flash for fast operations
    Given the operator navigates from one namespace to another
    And the namespace switch operation completes in 80 ms
    When the namespace switch is initiated
    Then no skeleton loader or spinner is displayed at any point
    And the resource list transitions directly from the previous content to the new content
    And the "AsyncResource" state never visibly enters "loading" from the operator's perspective

  Scenario: Loading state is accessible to VoiceOver
    Given VoiceOver is enabled
    When a resource list enters "loading" state
    Then the loading container announces "Loading" via VoiceOver
    When the resource list transitions to "failure" state
    Then VoiceOver announces the error title

  Scenario: Shimmer animation is suppressed when Reduce Motion is enabled
    Given the system accessibility setting "Reduce Motion" is enabled
    Or the operator has set the "reduceMotion" theme knob to true
    When a resource list enters "loading" state with shimmer presentation
    Then no repeating gradient animation is visible
    And a static low-opacity overlay is shown instead
    And the placeholder layout is still visible for spatial context
