# DDD role: BehaviouralSpecification
@adr-0051
Feature: Cluster strip pin and unpin
  As a Kubernetes operator managing multiple clusters
  I want to pin clusters to a vertical strip at the left edge of the window
  So that I can switch between active cluster sessions with a single click
  And have pinned clusters immediately visible without any navigation action

  Background:
    Given the application is running on macOS 14 or later
    And the operator has loaded at least one kubeconfig

  Scenario: Pinning a cluster adds an avatar chip to the cluster strip
    Given the cluster strip contains no pinned clusters
    And the operator has a cluster "prod-aks" in the kubeconfig
    When the operator clicks the "+" button at the bottom of the cluster strip
    And selects "prod-aks" from the cluster picker
    Then the cluster strip shows an avatar chip for "prod-aks"
    And the avatar displays initials "PA" derived from the cluster display name
    And the avatar background color is deterministically assigned from the palette

  Scenario: Avatar color is consistent across launches
    Given the cluster "prod-aks" with clusterId "01900000-0000-7000-8000-000000000010" is pinned
    When the application is restarted
    Then the cluster strip shows the avatar for "prod-aks"
    And the avatar background color is identical to the color before restart
    And the color is derived from hash("01900000-0000-7000-8000-000000000010") mod 8

  Scenario: Clicking a pinned cluster chip switches the active cluster
    Given the cluster strip has two pinned clusters: "prod-aks" and "staging-eks"
    And the active cluster is "prod-aks"
    When the operator clicks the "staging-eks" avatar chip
    Then the sidebar tree switches to show the resource tree for "staging-eks"
    And the tab bar updates to show tabs belonging to "staging-eks"
    And the status bar updates to display "staging-eks" as the active cluster

  Scenario: Status ring reflects cluster connection health
    Given the cluster "prod-aks" is pinned and connected
    And the avatar shows a green status ring
    When the cluster "prod-aks" loses connectivity
    Then the avatar ring changes to red within 5 seconds
    And no manual refresh is required
    And the change is driven by a ClusterSessionClosed domain event

  Scenario: Drag-reordering pins updates the persisted pin order
    Given the cluster strip has three pinned clusters in order: "alpha", "beta", "gamma"
    When the operator drags the "gamma" chip to the top position
    Then the strip displays clusters in order: "gamma", "alpha", "beta"
    And the new pin order is persisted to "workspace/cluster-strip-pins.json"
    And the pinOrder values are contiguous starting at 0

  Scenario: Unpinning a cluster removes it from the strip
    Given the cluster "local-kind" is pinned in the strip
    When the operator right-clicks the "local-kind" chip
    And selects "Unpin cluster" from the context menu
    Then the "local-kind" chip is removed from the cluster strip
    And the remaining chips reorder to fill the gap
    And the updated pin list is persisted to "workspace/cluster-strip-pins.json"

  Scenario: Strip is restored after cold launch in the correct pin order
    Given three clusters are pinned in order: "prod-aks", "staging-eks", "local-kind"
    And "workspace/cluster-strip-pins.json" reflects this order
    When the application is cold-launched
    Then the cluster strip shows the three chips immediately during the launch sequence
    Before any cluster session health probe completes
    And the chips are displayed in the correct persisted order

  Scenario: Maximum pin limit prevents exceeding 16 clusters
    Given the cluster strip has 16 pinned clusters
    When the operator attempts to pin a 17th cluster
    Then an error toast is shown: "The cluster strip supports a maximum of 16 pinned clusters"
    And the 17th cluster is not added to the strip
    And the existing 16 pins are unchanged

  Scenario: Provider section grouping in sidebar tree reflects pinned cluster provider
    Given the cluster "prod-aks" is pinned and its providerKind is "aks"
    And the cluster "staging-eks" is pinned and its providerKind is "eks"
    When the operator views the sidebar tree
    Then the sidebar shows an "AKS" section header containing "prod-aks"
    And the sidebar shows an "EKS" section header containing "staging-eks"
    And empty provider sections are not shown
