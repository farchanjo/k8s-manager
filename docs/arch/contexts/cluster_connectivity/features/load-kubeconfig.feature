# DDD role: Feature
# Bounded context: cluster_connectivity
Feature: Load kubeconfig from disk

  As an operator on macOS
  I want K8sManager to read my kubeconfig file
  So that I can see every cluster, user, and context I have access to
  Without giving up my existing kubectl workflow

  Background:
    Given the application is freshly launched
    And the application has not yet stored any preferences

  Scenario: Default kubeconfig path is honoured
    Given the KUBECONFIG environment variable is not set
    And the file "~/.kube/config" exists and is well-formed
    When the cluster_connectivity context loads its kubeconfig
    Then the loaded source path resolves to "~/.kube/config"
    And the load report status is "success"
    And every declared context is enumerated

  Scenario: KUBECONFIG overrides the default path
    Given the KUBECONFIG environment variable is "/Users/farchanjo/projects/staging.kubeconfig"
    And that file exists and is well-formed
    When the cluster_connectivity context loads its kubeconfig
    Then the loaded source path is "/Users/farchanjo/projects/staging.kubeconfig"
    And the load report status is "success"

  Scenario: Multiple kubeconfigs are merged in KUBECONFIG order
    Given the KUBECONFIG environment variable is "/etc/dev:/etc/prod"
    And both files exist and are well-formed
    And both declare a context named "default"
    When the cluster_connectivity context loads its kubeconfig
    Then the merged kubeconfig contains exactly one context named "default"
    And the "default" entry comes from "/etc/dev"

  Scenario: Malformed YAML surfaces an actionable error
    Given the file "~/.kube/config" contains invalid YAML
    When the cluster_connectivity context loads its kubeconfig
    Then the load report status is "error"
    And the load report includes the line number of the parse failure
    And no cluster, user, or context entry is exposed to other contexts

  Scenario: A context that references an unknown cluster is rejected
    Given a kubeconfig declares a context "broken" with cluster "missing-cluster"
    And "missing-cluster" is not declared under clusters[]
    When the cluster_connectivity context loads its kubeconfig
    Then the load report includes a deny entry referencing "broken"
    And the "broken" context is not exposed to other contexts

  Scenario: External edit of the source file invalidates the load
    Given a kubeconfig has been loaded successfully
    And the source file's mtime advances by at least one second
    When the cluster_connectivity context observes the mtime change
    Then the loaded kubeconfig aggregate is reloaded from disk
    And consumers of the previous aggregate receive a "reloaded" event
