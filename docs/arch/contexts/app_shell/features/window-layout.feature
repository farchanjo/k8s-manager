# DDD role: Feature
# Bounded context: app_shell
Feature: Window layout and navigation structure

  As an operator on macOS
  I want the K8sManager window to honour my layout preferences and persist them
  So that my workspace is consistent across launches and across monitors

  Background:
    Given the application is installed as a Developer ID signed bundle
    And the operator has completed at least one successful launch
    And the local persistence store is available and readable

  Scenario: NavigationSplitView renders all three columns on first launch
    Given no persisted window layout exists
    When the operator launches the application for the first time
    Then the main window displays a sidebar column
    And the main window displays a content list column
    And the main window displays a detail pane column
    And the sidebar column width is 260 points
    And the content list column width is 420 points
    And the detail pane width is at least 480 points

  Scenario: Toggle sidebar hides the sidebar column
    Given the main window is visible with the sidebar column shown
    When the operator toggles the sidebar via the View menu
    Then the sidebar column is hidden
    And the content list column expands to fill the vacated space
    And the detail pane width is unchanged

  Scenario: Toggle inspector opens the inspector panel
    Given the main window is visible
    And the inspector panel is closed
    When the operator presses Command-Option-I
    Then the inspector panel becomes visible alongside the detail pane
    And the detail pane narrows to accommodate the inspector

  Scenario: Sidebar width persists across relaunches
    Given the operator drags the sidebar divider to set the sidebar column width to 310 points
    When the operator quits the application
    And the operator relaunches the application
    Then the sidebar column width is restored to 310 points

  Scenario: Window frame is restored on relaunch
    Given the operator has repositioned the main window to x=200 y=300 with width=1440 height=900
    When the operator quits the application
    And the operator relaunches the application
    Then the main window appears at approximately x=200 y=300
    And the main window width is approximately 1440 points
    And the main window height is approximately 900 points

  Scenario: Multi-monitor support — window restores to the correct screen
    Given the operator has two monitors connected
    And the main window is positioned on the secondary monitor
    When the operator quits the application
    And the operator relaunches the application with both monitors connected
    Then the main window appears on the secondary monitor at its last-known position

  Scenario: Fullscreen mode preserves column proportions
    Given the main window is visible with a sidebar column width of 280 points
    When the operator enters fullscreen mode via the green traffic-light button
    Then the application occupies the full screen
    And the sidebar column is visible
    And the content list and detail pane fill the remaining width proportionally
    And the sidebar column width remains 280 points when the operator exits fullscreen

  Scenario: Inspector visibility persists across relaunches
    Given the operator opens the inspector panel
    When the operator quits the application
    And the operator relaunches the application
    Then the inspector panel is open on launch without additional operator action
