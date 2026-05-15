# DDD role: Feature
# Bounded context: helm_management
Feature: Inspect a Helm release in detail

  As an operator managing a Kubernetes cluster
  I want to inspect the full details of a specific Helm release
  So that I can understand what manifests were applied, what values
  were used, what chart version is running, and what hooks are declared,
  without running helm get or helm status from the CLI

  Background:
    Given the application is running with a healthy cluster connection
    And the operator has selected cluster "prod-cluster" as the active context
    And the releases panel shows release "prometheus" in namespace "monitoring"
    And the operator has opened the detail view for "prometheus"

  Scenario: View the rendered manifest YAML for the current revision
    Given the #Release aggregate for "prometheus" revision 7 has been decoded
    And the manifestYAML field contains the full rendered template output
    When the operator selects the "Manifest" tab in the detail view
    Then the manifest panel displays the full YAML text of the rendered manifest
    And the YAML is presented in a read-only syntax-highlighted text area
    And a "Copy to clipboard" button is available in the manifest panel toolbar
    And the manifest is not truncated regardless of its length

  Scenario: View the user-supplied values for the current revision
    Given the #Release aggregate for "prometheus" revision 7 has valuesJSON
      containing overrides for keys "alertmanager.enabled" and "grafana.service.type"
    When the operator selects the "Values" tab in the detail view
    Then the values panel displays the user-supplied values as formatted JSON
    And "alertmanager.enabled" is shown with its override value
    And "grafana.service.type" is shown with its override value
    And a "Copy to clipboard" button is available in the values panel toolbar

  Scenario: View chart metadata for the current revision
    Given the #Release aggregate for "prometheus" revision 7 has chart metadata:
      | field       | value                     |
      | name        | kube-prometheus-stack     |
      | version     | 56.3.0                    |
      | appVersion  | 0.71.2                    |
      | apiVersion  | v2                        |
      | description | Kubernetes monitoring stack |
    When the operator selects the "Chart" tab in the detail view
    Then the chart panel shows name "kube-prometheus-stack"
    And the chart panel shows version "56.3.0"
    And the chart panel shows appVersion "0.71.2"
    And the chart panel shows apiVersion "v2"
    And the chart panel shows the description text

  Scenario: View revision history for a release
    Given the cluster has four Secrets for release "prometheus" in namespace "monitoring"
    And the revisions in ascending order are: 4 (deployed), 3 (superseded), 2 (superseded), 1 (superseded)
    When the operator selects the "History" tab in the detail view
    Then the history panel displays four rows in descending order of revision
    And the row for revision 4 shows status "deployed" and a chart version
    And the row for revision 3 shows status "superseded" and its deployment timestamp
    And the row for revision 2 shows status "superseded" and its deployment timestamp
    And the row for revision 1 shows status "superseded" and its deployment timestamp
    And each row has a "Rollback to this revision" button that is enabled for revisions 1 through 3

  Scenario: View declared hooks for the current revision
    Given the #Release aggregate for "prometheus" revision 7 has two hooks:
      | name                    | kind | events         | weight |
      | pre-install-configcheck | Job  | pre-install    | 0      |
      | post-upgrade-migration  | Job  | post-upgrade   | 10     |
    When the operator selects the "Hooks" tab in the detail view
    Then the hooks panel displays two rows
    And the row for "pre-install-configcheck" shows kind "Job", event "pre-install", weight "0"
    And the row for "post-upgrade-migration" shows kind "Job", event "post-upgrade", weight "10"
    And each hook row has a "View manifest" link that opens a read-only YAML panel for the hook manifest
