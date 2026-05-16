# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (cluster discovery), DomainService (kubeconfig materialisation)
# Context: cluster_connectivity
# Related ADRs: ADR-0055 (Cloud provider cluster discovery), ADR-0018 (Native cloud credential resolution), ADR-0054 (Welcome tab)
Feature: GCP GKE cluster discovery

  As an operator managing GKE clusters on Google Cloud
  I want K8sManager to enumerate my GKE clusters using my Application Default Credentials
  So that I can import kubeconfig entries without running gcloud container clusters get-credentials
  And without having the gcloud SDK installed

  Background:
    Given the application is running with no subprocess execution entitlements
    And the welcome tab is visible with the "Add Clusters from GKE" action available
    And the operator has not yet imported any GKE cluster

  Scenario: Discover and import GKE clusters using Application Default Credentials
    Given "~/.config/gcloud/application_default_credentials.json" contains valid user credentials
      with a refresh token for principal "operator@example.com"
    And the principal has "container.clusters.list" permission on project "my-k8s-project"
    And project "my-k8s-project" contains two GKE clusters:
      "prod-gke" in location "us-central1"
      and "staging-gke" in location "europe-west1"
    When the operator activates "Add Clusters from GKE" on the welcome tab
    And the project picker shows "my-k8s-project" and the operator confirms it
    And the operator selects both "prod-gke" and "staging-gke" in the discovery preview
    And the operator confirms the import
    Then two KubeconfigEntry values are written to the in-memory kubeconfig aggregate
    And the context name for "prod-gke" follows the gcloud naming convention:
      """
      gke_my-k8s-project_us-central1_prod-gke
      """
    And the exec block for each entry uses command "gke-gcloud-auth-plugin" with no additional args
    And both clusters appear in the cluster strip under the "GKE" provider section
    And no subprocess was invoked during the entire discovery and import sequence

  Scenario: No GCP credentials configured — actionable error is surfaced
    Given the environment variable GOOGLE_APPLICATION_CREDENTIALS is not set
    And no file exists at "~/.config/gcloud/application_default_credentials.json"
    When the operator activates "Add Clusters from GKE" on the welcome tab
    Then no GKE API call is made
    And an error sheet is presented with the message:
      """
      No Google Cloud credentials found. Run application default credentials setup
      or set GOOGLE_APPLICATION_CREDENTIALS to a service account key file before retrying.
      """
    And the error sheet contains a "Learn more" link to the ADC documentation
    And the welcome tab remains open and the operator can retry without restarting the application

  Scenario: Project and location filter scopes discovery to specified project and locations only
    Given "~/.config/gcloud/application_default_credentials.json" contains valid user credentials
    And the principal has access to projects "project-a" and "project-b"
    And "project-a" contains GKE clusters in locations "us-central1" and "asia-east1"
    And "project-b" contains a GKE cluster in location "europe-west1"
    When the operator activates "Add Clusters from GKE" on the welcome tab
    And the project picker lists both projects
    And the operator selects only "project-a"
    And the operator additionally restricts locations to "us-central1" only
    And the operator confirms discovery
    Then the discovery adapter calls the GKE clusters API only for project "project-a"
      with location filter "us-central1"
    And clusters from "project-b" are not included in the discovery preview
    And clusters from "asia-east1" in "project-a" are not included in the discovery preview
    And the preview shows only the clusters from "project-a" in "us-central1"

  Scenario: Partial import — one cluster describe fails, others succeed
    Given "~/.config/gcloud/application_default_credentials.json" contains valid user credentials
    And project "my-k8s-project" contains three GKE clusters:
      "alpha-gke", "beta-gke", "gamma-gke" all in location "us-central1"
    And the GKE API returns a 503 error for cluster "beta-gke" during the describe step
    When the operator activates "Add Clusters from GKE" on the welcome tab
    And the project picker is confirmed with "my-k8s-project"
    And the operator selects all three clusters in the discovery preview and confirms import
    Then KubeconfigEntry values are written for "alpha-gke" and "gamma-gke"
    And no KubeconfigEntry is written for "beta-gke"
    And a DiscoveryWarning is emitted identifying "beta-gke" as the failed descriptor with the
      HTTP 503 status code included in the warning detail
    And the warning is visible in the application notification stream
    And the operator is not blocked from using "alpha-gke" and "gamma-gke" immediately
