# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (security read models), ReadModel (SecurityPostureSummary)
# Context: app_shell
# Related ADRs: ADR-0068 (Security Center sidebar surface), ADR-0049 (App shell policy coverage), ADR-0050 (Resource navigation taxonomy)
Feature: Security Center sidebar entry

  Background:
    Given a cluster session is active and connected
    And the per-cluster sidebar tree is rendered for that cluster

  Scenario: Security Center entry is visible for every connected cluster
    Given the sidebar tree is expanded to the cluster root
    When the operator scrolls past the Custom Resources section
    Then a "Security Center" section header is visible below the Custom Resources section
    And the "Security Center" section header is keyboard-focusable
    And the "Security Center" section header has a non-empty accessibility label

  Scenario: Security Center expands to exactly four sub-entries in fixed order
    Given the "Security Center" section is collapsed
    When the operator activates the "Security Center" section header
    Then the section expands to reveal exactly four sub-entries
    And the first sub-entry is labelled "Overview"
    And the second sub-entry is labelled "Images"
    And the third sub-entry is labelled "Resources"
    And the fourth sub-entry is labelled "Roles"
    And no additional sub-entries are present under the "Security Center" section

  Scenario: Overview sub-entry shows the cluster security posture summary
    Given at least one pod is running with no explicit runAsNonRoot constraint
    And at least one namespace has no pod-security.kubernetes.io/enforce label
    When the operator selects the "Overview" sub-entry
    Then the content area renders the SecurityOverviewView
    And a count labelled "Pods running as root" is visible and greater than zero
    And a count labelled "Namespaces missing PodSecurity admission labels" is visible and greater than zero
    And a count labelled "Network policies" is visible
    And a count labelled "mTLS-protected services" is visible

  Scenario: Images sub-entry lists unique container images grouped from running pods
    Given three pods are running with two distinct container image references
    When the operator selects the "Images" sub-entry
    Then the content area renders the SecurityImagesView
    And exactly two image rows are visible
    And each row displays the image reference including registry and tag or digest
    And each row indicates whether a digest is declared

  Scenario: Roles sub-entry sorts cluster-admin first and highlights dangerous verbs
    Given the cluster has a ClusterRole named "cluster-admin" with verb "*" on all resources
    And the cluster has a namespaced Role named "pod-reader" with verb "get" on pods
    When the operator selects the "Roles" sub-entry
    Then the content area renders the SecurityRolesView
    And the first row displays the ClusterRole named "cluster-admin"
    And the "cluster-admin" row carries a risk badge indicating wildcard verb privileges
    And the "pod-reader" Role row appears after all ClusterRole rows
