# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (applications aggregator), ReadModel (ApplicationRow)
# Context: resource_browser
# Related ADRs: ADR-0067 (Applications cluster scope), ADR-0015 (Helm native phased), ADR-0050 (Resource navigation taxonomy)
Feature: Applications scope — Helm releases aggregated per cluster

  Background:
    Given the operator has connected to a cluster named "production"
    And the cluster session is healthy
    And the operator has completed onboarding

  Scenario: Applications entry is visible per cluster in the sidebar tree
    Given the sidebar tree is rendered for cluster "production"
    When the operator inspects the per-cluster tree nodes
    Then an "Applications" leaf node is present in the tree
    And "Applications" appears between the "Overview" node and the "Nodes" node
    And the "Applications" node is not a disclosure group — it has no child nodes

  Scenario: Empty state is shown when the cluster has no Helm releases
    Given the cluster "production" has no Helm releases in any namespace
    When the operator clicks "Applications" in the sidebar tree
    Then a tab with kind "applicationsList" is opened for cluster "production"
    And the tab content shows a centred empty state with heading "No Helm releases in this cluster"
    And the empty state body reads "Try `helm install` or import a release via the Helm tab."
    And a secondary action button labelled "Go to Helm" is visible and keyboard-focusable

  Scenario: Applications list shows Name, Chart, Version, Status, Updated, Namespace, and Revision columns
    Given the cluster "production" has the following Helm releases in namespace "default":
      | name          | chart         | version | status   | namespace | revision |
      | nginx-ingress | nginx-ingress | 4.10.0  | deployed | default   | 3        |
      | cert-manager  | cert-manager  | 1.14.2  | deployed | default   | 1        |
    When the operator opens the "Applications" tab for cluster "production"
    Then the list displays exactly 2 rows
    And each row exposes the columns Name, Chart, Version, Status, Updated, Namespace, and Revision
    And the row for "nginx-ingress" shows chart "nginx-ingress", version "4.10.0", status "deployed", namespace "default", and revision "3"
    And the list is sorted by Name ascending by default

  Scenario: Namespace filter narrows the Applications list to the selected namespace
    Given the cluster "production" has Helm releases in namespaces "default", "monitoring", and "kube-system"
    And the global namespace filter is set to "monitoring"
    When the operator opens the "Applications" tab for cluster "production"
    Then the list shows only releases whose namespace is "monitoring"
    And releases in "default" and "kube-system" are not present in the list

  Scenario: Clicking a release row opens the release detail in the standalone Helm subtree
    Given the cluster "production" has a Helm release named "cert-manager" in namespace "default"
    And the "Applications" tab is open showing the release list
    When the operator clicks the row for release "cert-manager"
    Then a tab with kind "helmDetail" is opened for release "cert-manager" in namespace "default" on cluster "production"
    And the "Applications" tab remains open alongside the new "helmDetail" tab
    And the "helmDetail" tab renders the release detail view as defined in ADR-0015
