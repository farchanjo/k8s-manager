# DDD role: Feature
# Bounded context: helm_management
Feature: List Helm releases in a Kubernetes cluster

  As an operator managing a Kubernetes cluster
  I want to view all Helm releases deployed in the cluster
  So that I can understand what is installed, in which namespaces,
  and at which revision, without leaving K8sManager or running helm CLI

  Background:
    Given the application is running with a healthy cluster connection
    And the operator has selected cluster "prod-cluster" as the active context
    And the Helm releases panel is open

  Scenario: List all Helm releases across all namespaces
    Given the cluster has Helm release Secrets for the following releases:
      | name         | namespace   | revision | status   |
      | nginx-ingress | ingress-nginx | 3      | deployed |
      | cert-manager  | cert-manager  | 1      | deployed |
      | prometheus    | monitoring    | 7      | deployed |
    And each Secret has type "helm.sh/release.v1" and label "owner=helm"
    When the helm_management context lists Secrets with label "owner=helm" across all namespaces
    Then the releases panel displays one row per logical release (grouped by name and namespace)
    And the row for "nginx-ingress" shows namespace "ingress-nginx", revision "3", status "deployed"
    And the row for "cert-manager" shows namespace "cert-manager", revision "1", status "deployed"
    And the row for "prometheus" shows namespace "monitoring", revision "7", status "deployed"
    And all three rows are visible without scrolling for a list of three items

  Scenario: Filter releases by namespace
    Given the cluster has Helm releases in namespaces "default", "monitoring", and "ingress-nginx"
    And the total number of release rows across all namespaces is twelve
    When the operator selects namespace "monitoring" from the namespace picker
    Then the releases panel shows only the releases whose namespace is "monitoring"
    And no release from namespace "default" or "ingress-nginx" appears in the list

  Scenario: Group multiple revisions and show only the latest deployed revision
    Given the cluster has four Secrets for release "prometheus" in namespace "monitoring":
      | Secret name                               | revision | status     |
      | sh.helm.release.v1.prometheus.v4          | 4        | deployed   |
      | sh.helm.release.v1.prometheus.v3          | 3        | superseded |
      | sh.helm.release.v1.prometheus.v2          | 2        | superseded |
      | sh.helm.release.v1.prometheus.v1          | 1        | superseded |
    When the helm_management context decodes all four Secrets and groups by (name, namespace)
    Then the releases panel shows one row for "prometheus" in "monitoring"
    And the row shows revision "4" and status "deployed"
    And the three superseded revisions are not shown in the main list
    And the three superseded revisions are accessible via the history view for "prometheus"

  Scenario: Superseded releases are hidden by default in the main list
    Given the cluster has a Helm release "old-nginx" in namespace "default" with status "superseded"
    And the cluster has a Helm release "active-app" in namespace "default" with status "deployed"
    When the operator views the releases panel without enabling the "show superseded" filter
    Then "active-app" appears in the releases list
    And "old-nginx" does not appear in the releases list
    When the operator enables the "Show superseded releases" toggle
    Then "old-nginx" appears in the releases list with status "superseded"
    And "active-app" continues to appear in the releases list

  Scenario: Cluster using a non-secret Helm driver degrades gracefully
    Given the cluster has no Secrets with type "helm.sh/release.v1" in any namespace
    And the cluster has Deployments with annotation "app.kubernetes.io/managed-by=Helm"
    When the helm_management context queries for Helm release Secrets and finds none
    Then the releases panel displays a degradation banner with the message
      """
      Helm releases not visible — the cluster may be using a non-secret Helm driver
      (configmap or sql). Manual inspection via the Resource Browser is available.
      """
    And no error dialog is shown to the operator
    And the Resource Browser link in the banner navigates to the resource_browser context

  Scenario: Release with manifest YAML near the etcd Secret size limit still renders
    Given the cluster has a Helm release "large-app" in namespace "default"
    And the release Secret contains a manifest YAML of 900 kilobytes
    And the Secret total size including metadata is below the 1048576-byte etcd limit
    When the helm_management context decodes the release Secret for "large-app"
    Then the #Release aggregate is materialised without error
    And the releases panel displays a row for "large-app" with status "deployed"
    And the detail view renders the manifest YAML in a scrollable text area
    And no truncation warning is shown to the operator

  Scenario: Release Secret with PEM certificate in manifest is rejected
    Given the cluster has a Helm release "tls-app" in namespace "default"
    And the decoded manifest YAML for "tls-app" contains a "-----BEGIN CERTIFICATE-----" block
    When the helm_management context evaluates the release_decoder_invariants policy for "tls-app"
    Then the policy fires the "embedded_credential_detected" deny rule
    And the release "tls-app" is NOT materialised into a #Release aggregate
    And the releases panel shows "tls-app" with status "decode error" and a warning icon
    And the warning tooltip reads "rendered manifest contains PEM-encoded credential material"
