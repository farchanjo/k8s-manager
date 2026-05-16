# DDD role: BehaviouralSpecification
@adr-0050
Feature: Tab open from sidebar tree
  As a Kubernetes operator
  I want clicking a resource kind node in the sidebar tree to open a tab in the tab bar
  So that I can maintain multiple resource views simultaneously without losing navigation context

  Background:
    Given the application is running on macOS 14 or later
    And the operator has an active session for cluster "prod-aks"
    And the sidebar tree is showing the resource tree for "prod-aks"

  Scenario: Clicking a workload kind opens a resourceList tab
    Given the sidebar tree shows the "Workloads" section expanded
    When the operator clicks "Deployments" in the sidebar tree
    Then a new tab opens in the tab bar with label "Deployments"
    And the tab chip shows the "prod-aks" cluster avatar
    And the tab chip shows the Deployment SF Symbol icon
    And the content area shows the list of Deployments in the active namespace
    And a watch stream is established for Deployments in the active namespace

  Scenario: Clicking the same node twice focuses the existing tab, not a duplicate
    Given a "Deployments" tab is already open for namespace "default"
    When the operator clicks "Deployments" in the sidebar tree again
    Then no new tab is created
    And the existing "Deployments" tab is brought to focus
    And the watch stream count remains unchanged
    And the tab bar shows exactly one "Deployments" tab

  Scenario: Opening a tab for a different namespace creates a distinct tab
    Given a "Pods" tab is open for namespace "default"
    And the operator changes the active namespace to "kube-system"
    When the operator clicks "Pods" in the sidebar tree
    Then a new "Pods" tab opens for namespace "kube-system"
    And the tab bar now shows two "Pods" tabs: one for "default" and one for "kube-system"
    And each tab has its own independent watch stream

  Scenario: Tab chip context menu offers close, pin, and namespace info
    Given a "Services" tab is open for namespace "default"
    When the operator right-clicks the "Services" tab chip
    Then a context menu appears with options: "Close Tab", "Pin Tab", "Copy Namespace"
    And the namespace shown in the context menu is "default"

  Scenario: Clicking a cluster overview node opens a clusterOverview tab
    Given the sidebar tree shows "Overview" at the top of the cluster tree
    When the operator clicks "Overview"
    Then a "clusterOverview" tab opens for cluster "prod-aks"
    And the tab chip shows no namespace (cluster-scoped overview)
    And the content area shows the synthetic ClusterOverview read model

  Scenario: Opening a tab for a CRD kind creates a resourceList tab with isDynamic context
    Given the "Custom Resources" sidebar section is expanded
    And the API group "argoproj.io" has been discovered with kind "Application"
    When the operator clicks "Application" under "argoproj.io"
    Then a "resourceList" tab opens with kindName "Application" and apiGroup "argoproj.io"
    And a watch stream is established via GVRWatchPort for the "applications" resource

  Scenario: Tab identity tuple prevents duplicate tabs across identical tree node clicks
    Given a tab is open with identity (clusterId="prod-aks", tabKind="resourceList", namespace="default", kindName="ConfigMap")
    When the operator clicks "ConfigMaps" in the sidebar tree with namespace "default" active
    Then the existing tab is focused
    And the OpenTabsActor is called with focusTab, not openTab
    And no new watch stream is started

  Scenario: Tab bar shows cluster avatar initials matching the active cluster chip
    Given the cluster "prod-aks" has avatar initials "PA" and colorIndex 0
    When a "Pods" tab is opened for "prod-aks"
    Then the tab chip displays initials "PA" in the colorIndex 0 color
    And the initials and color match the cluster strip avatar for "prod-aks"
