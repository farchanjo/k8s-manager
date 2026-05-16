# DDD role: BehaviouralSpecification
@adr-0050 @adr-0036
Feature: Tab close cancels associated watch streams
  As a Kubernetes operator
  I want closing a tab to cancel all watch streams associated with that tab
  So that the application does not hold open unnecessary connections to the Kubernetes API
  And the watch stream budget is reclaimed for other tabs

  Background:
    Given the application is running on macOS 14 or later
    And the operator has an active session for cluster "prod-aks"
    And the watch stream budget for "prod-aks" has capacity

  Scenario: Closing a resourceList tab cancels its watch stream
    Given a "Pods" resourceList tab is open for namespace "default"
    And a watch stream for (kind=Pod, namespace=default) is active on ClusterSessionActor
    When the operator clicks the close button on the "Pods" tab chip
    Then the "Pods" tab is removed from the tab bar
    And the watch stream for (kind=Pod, namespace=default) is cancelled
    And the watch Task is removed from OpenTabsActor's watcher registry
    And the active watch stream count for "prod-aks" decreases by 1

  Scenario: Closing a pinned tab requires unpinning first
    Given a "Deployments" tab is pinned
    When the operator clicks the close button on the "Deployments" tab chip
    Then no tab is closed
    And an inline tooltip appears: "Unpin this tab before closing"
    And the watch stream for Deployments remains active

  Scenario: Closing a resourceDetail tab cancels its watch stream
    Given a resourceDetail tab is open for Pod "backend-xyz" in namespace "default"
    And a watch stream for (kind=Pod, name=backend-xyz, namespace=default) is active
    When the operator closes the resourceDetail tab
    Then the watch stream for that specific pod is cancelled
    And the watcher registry entry for that tabId is removed
    And the pod detail no longer receives live updates

  Scenario: Closing a clusterOverview tab does not cancel cluster session watches
    Given a "clusterOverview" tab is open for "prod-aks"
    And separate "Pods" and "Services" tabs are also open, each with their own watches
    When the operator closes the "clusterOverview" tab
    Then only the clusterOverview tab is removed
    And the watch streams for Pods and Services remain active and unaffected

  Scenario: Watch stream is evicted by LRU policy when watch budget is exceeded
    Given the watch stream budget for "prod-aks" is 16 concurrent streams
    And 16 resourceList tabs are open, each with an active watch
    When the operator opens a 17th resourceList tab
    Then the watch stream for the least recently used tab is evicted
    And the evicted tab chip shows a "paused" or refresh indicator
    And the new tab's watch stream is established
    And the total active watch count remains at 16

  Scenario: Evicted tab watch can be manually resumed
    Given a "ConfigMaps" tab has been evicted from the watch budget
    And its tab chip shows a refresh indicator
    When the operator clicks the refresh indicator on the "ConfigMaps" tab chip
    Then a new watch stream is started for ConfigMaps using the current resource version
    And the tab transitions from "paused" back to "live" state

  Scenario: Session close cancels all watches for that cluster
    Given three tabs are open for cluster "staging-eks": Pods, Services, Deployments
    And each tab has an active watch stream
    When the cluster session for "staging-eks" is closed
    Then all three watch streams are cancelled via Swift Task cancellation
    And all three tab chips show a "disconnected" indicator
    And a ClusterSessionClosed domain event is emitted on the DomainEventBusPort
    And OpenTabsActor transitions all affected tabs to the disconnected state

  Scenario: Sidebar tree click on existing tab does not start a second watch
    Given a "Nodes" tab is already open with an active watch
    When the operator clicks "Nodes" in the sidebar tree
    Then the existing tab is brought to focus via focusTab command
    And no new watch stream is started
    And the watch stream count for "Nodes" remains at 1
