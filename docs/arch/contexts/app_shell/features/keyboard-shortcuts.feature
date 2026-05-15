# DDD role: Feature
# Bounded context: app_shell
Feature: Keyboard shortcuts for resource operations and navigation

  As a Kubernetes operator on macOS
  I want a coherent set of keyboard shortcuts that combine k9s-style list bindings with macOS-native Cmd shortcuts
  So that I can operate entirely without a mouse while following familiar muscle memory from both ecosystems

  Background:
    Given the application is running with at least one cluster connected
    And the resource browser is visible with at least one resource row in the list
    And the operator has not enabled vim-style j/k navigation in settings

  Scenario: Single-key log shortcut opens log stream when resource row is focused
    Given a Pod resource row is focused in the resource browser
    When the operator presses the "l" key
    Then a live log stream panel opens for the selected pod
    And the log stream panel has keyboard focus
    And the resource browser list retains its selection

  Scenario: Single-key exec shortcut opens shell when pod row is focused
    Given a Pod resource row is focused in the resource browser
    When the operator presses the "s" key
    Then an exec shell terminal opens for the selected pod
    And the terminal pane has keyboard focus

  Scenario: Single-key "s" on a Node row opens a node debug session
    Given a Node resource row is focused in the resource browser
    When the operator presses the "s" key
    Then a privileged node debug session is initiated
    And the terminal pane has keyboard focus
    And the session label indicates it is a node debug session

  Scenario: Single-key shortcuts do not fire when a text field has focus
    Given a text field inside the YAML editor has keyboard focus
    When the operator presses the "l" key
    Then the character "l" is inserted into the text field
    And no log stream panel opens

  Scenario: Single-key shortcuts do not fire when an embedded terminal pane has focus
    Given an embedded terminal pane has keyboard focus
    When the operator presses the "d" key
    Then the character "d" is sent to the terminal process
    And no describe panel opens

  Scenario: Cmd-Delete triggers resource deletion with a confirmation dialog
    Given a Deployment resource row is focused in the resource browser
    When the operator presses Cmd-Delete
    Then a confirmation dialog appears with the resource name and kind
    And the dialog presents a destructive confirmation button and a cancel button
    When the operator confirms the deletion
    Then a delete request is sent to the API server for the selected resource
    And the resource row is removed from the list after the API server acknowledges

  Scenario: Cmd-1 through Cmd-9 switch to pinned cluster slots
    Given the operator has pinned three clusters in settings slots 1, 2, and 3
    When the operator presses Cmd-2
    Then the active cluster switches to the cluster in slot 2
    And the sidebar cluster indicator updates to show the name of the cluster in slot 2
    And all resource lists refresh to show resources from the new cluster

  Scenario: Ctrl-N cycles to the next pinned namespace
    Given the operator has pinned namespaces "default", "kube-system", and "monitoring"
    And the current namespace is "default"
    When the operator presses Ctrl-N
    Then the current namespace changes to "kube-system"
    And the resource list refreshes to show resources in "kube-system"
    When the operator presses Ctrl-N twice more
    Then the current namespace cycles back to "default"

  Scenario: Cmd-bracket keys navigate resource view history
    Given the operator has viewed three different resource detail panels in sequence
    When the operator presses Cmd-[
    Then the detail panel shows the previously viewed resource
    When the operator presses Cmd-]
    Then the detail panel shows the resource that was viewed after the previous one

  Scenario: Question-mark key shows the hotkey help overlay
    Given a resource list row is focused in the resource browser
    When the operator presses the "?" key
    Then a hotkey help overlay appears listing all active shortcut bindings
    And the overlay is navigable via keyboard without a mouse
    And VoiceOver announces each row as key name followed by action description
    When the operator presses Escape
    Then the overlay is dismissed and focus returns to the resource list row
