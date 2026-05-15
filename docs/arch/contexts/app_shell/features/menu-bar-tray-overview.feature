Feature: Menu bar tray overview
  As a K8sManager operator
  I want a persistent macOS menu bar status item with a popover
  So that I can monitor and navigate my Kubernetes clusters without opening the main window

  Background:
    Given the application has launched successfully
    And at least one cluster context is configured in the kubeconfig
    And the active context is "staging"

  Scenario: Tray icon appears in the menu bar after launch
    Given the application is running
    When I observe the macOS system menu bar
    Then the K8sManager status item is present in the menu bar
    And the status item displays the Kubernetes helm template image
    And the template image honours the current macOS Light or Dark appearance
    And the status item has a VoiceOver accessibility label of "K8sManager"

  Scenario: Left-clicking the status item opens the popover
    Given the tray icon is visible in the menu bar
    When I left-click the K8sManager status item
    Then an NSPopover appears anchored to the status item button
    And the popover width is approximately 360 points
    And the popover height is between 400 and 600 points
    And the popover header displays the active context name "staging"
    And the popover header displays a status badge for the active cluster
    And the popover is visible on screen with a directional arrow pointing to the status item

  Scenario: Cluster picker in the header switches the active context
    Given the popover is open
    And the following contexts are configured: "production", "staging", "dev"
    And the active context is "staging"
    When I expand the cluster selector dropdown in the popover header
    And I select "production" from the dropdown
    Then the context_navigation bounded context receives a context switch request for "production"
    And an ActiveContextChanged event is emitted within 500 milliseconds
    And the popover header updates to display "production" as the active context
    And all metric widgets begin loading with refreshed data for "production"
    And the main window title bar also reflects "production" as the active context

  Scenario: Status badge reflects the health of the active cluster
    Given the popover is open
    And the cluster_connectivity bounded context reports the active cluster health as "warning"
    When the TrayRefreshScheduler completes a refresh cycle
    Then the status badge in the popover header displays a warning indicator
    And the status badge colour matches the statusWarning design token
    And the NSStatusItem icon shows an orange overlay dot
    And the VoiceOver accessibility value for the status badge announces "cluster status: warning"

  Scenario: Popover closes when clicking outside while not pinned
    Given the popover is open
    And popoverPinned is false
    When I click anywhere outside the popover area
    Then the popover dismisses
    And the tray icon remains in the menu bar
    And if backgroundRefreshEnabled is false then all Combine subscriptions are cancelled

  Scenario: Right-clicking the status item opens the native NSMenu
    Given the tray icon is visible in the menu bar
    When I right-click the K8sManager status item
    Then a native NSMenu appears
    And the menu contains the item "Open K8sManager"
    And the menu contains the item "Pause Refresh"
    And the menu contains the item "Settings"
    And the menu contains the item "Quit K8sManager"
    And no NSPopover is shown during a right-click interaction
    And selecting "Open K8sManager" brings the main window to the foreground
