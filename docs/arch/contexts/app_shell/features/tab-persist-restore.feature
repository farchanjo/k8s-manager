# DDD role: BehaviouralSpecification
@adr-0050 @adr-0026
Feature: Tab persistence and restore across application launches
  As a Kubernetes operator
  I want my open tabs to be restored when I relaunch the application
  So that I can resume my workflow without having to manually re-open every view

  Background:
    Given the application is running on macOS 14 or later
    And the operator has clusters "prod-aks" and "staging-eks" pinned in the cluster strip

  Scenario: Open tabs are persisted within 500 ms of any tab mutation
    Given the operator has 3 tabs open for cluster "prod-aks"
    When the operator opens a fourth tab "Namespaces" for cluster "prod-aks"
    Then the updated tab list is persisted to "clusters/prod-aks/open-tabs.json"
    Within 500 ms of the openTab command completing
    And the persisted file reflects all 4 tabs in the correct order

  Scenario: resourceList tabs are restored after cold launch
    Given "clusters/prod-aks/open-tabs.json" contains 3 resourceList tabs:
      - Pods in namespace "default"
      - Deployments in namespace "production"
      - Services in namespace "default"
    When the application is cold-launched
    And the cluster session for "prod-aks" becomes available
    Then all 3 tabs are restored in the tab bar in the same order
    And a watch stream is established for each restored tab
    And the active tab is the one that was active when the application quit

  Scenario: resourceDetail tabs are restored only after cluster session is available
    Given "clusters/prod-aks/open-tabs.json" contains a resourceDetail tab for Pod "api-server-xyz"
    When the application is cold-launched
    And the cluster session for "prod-aks" is not yet established
    Then the tab chip is shown in the tab bar with a "loading" indicator
    When the cluster session for "prod-aks" becomes available
    Then the resourceDetail tab is restored with a live watch for "api-server-xyz"
    And the loading indicator is replaced with the pod detail view

  Scenario: Pinned tabs survive application restart
    Given a "Deployments" tab for namespace "production" is pinned
    And the application is quit
    When the application is relaunched
    Then the "Deployments" tab is restored in the tab bar
    And the tab chip shows the pinned indicator
    And the tab cannot be closed via the close button without unpinning first

  Scenario: Tabs for unavailable clusters are cleaned up on restore
    Given "clusters/removed-cluster/open-tabs.json" exists with 2 tabs
    But the cluster "removed-cluster" is not in the kubeconfig
    When the application is cold-launched
    Then the tabs for "removed-cluster" are not restored
    And "clusters/removed-cluster/open-tabs.json" is not recreated
    And no error toast is shown for the stale tab state

  Scenario: Maximum 20 tabs per cluster is enforced on restore
    Given "clusters/prod-aks/open-tabs.json" was written with 20 tabs
    When the application is cold-launched
    Then all 20 tabs are restored
    When the operator opens a 21st tab for "prod-aks"
    Then the oldest non-pinned tab is automatically closed
    And a toast notification appears: "A tab was closed to stay within the 20-tab limit"
    And the closed tab's watch stream is cancelled

  Scenario: Tab restore does not block the UI during cold launch
    Given "clusters/prod-aks/open-tabs.json" contains 15 tabs
    When the application is cold-launched
    Then the application window is displayed and interactive immediately
    And tab watch streams are re-established asynchronously in the background
    And each tab chip transitions from "loading" to "live" as its watch stream connects
    And no UI freeze or spinner blocks the window during this process

  Scenario: Cross-cluster tabs persist independently per cluster
    Given cluster "prod-aks" has 3 open tabs
    And cluster "staging-eks" has 2 open tabs
    When the operator quits the application
    Then "clusters/prod-aks/open-tabs.json" contains exactly 3 tabs
    And "clusters/staging-eks/open-tabs.json" contains exactly 2 tabs
    When the application is relaunched
    Then "prod-aks" tabs and "staging-eks" tabs are both restored concurrently
    And tabs from one cluster do not appear in the other cluster's tab bar
