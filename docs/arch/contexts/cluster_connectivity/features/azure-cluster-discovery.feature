# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (cluster discovery), DomainService (kubeconfig materialisation)
# Context: cluster_connectivity
# Related ADRs: ADR-0055 (Cloud provider cluster discovery), ADR-0018 (Native cloud credential resolution), ADR-0054 (Welcome tab)
Feature: Azure AKS cluster discovery

  As an operator managing AKS clusters on Azure
  I want K8sManager to enumerate my AKS clusters using my current Azure credentials
  So that I can import kubeconfig entries without running az aks get-credentials
  And without having the Azure CLI installed

  Background:
    Given the application is running with no subprocess execution entitlements
    And the welcome tab is visible with the "Add Clusters from AKS" action available
    And the operator has not yet imported any AKS cluster

  Scenario: Discover and import AKS clusters using MSAL device-code credentials
    Given the operator has completed MSAL device-code sign-in for tenant "contoso.onmicrosoft.com"
    And the signed-in principal has "Azure Kubernetes Service Cluster User Role" on subscription "sub-prod"
    And subscription "sub-prod" contains AKS clusters "prod-aks" in resource group "rg-prod"
      and "staging-aks" in resource group "rg-staging"
    When the operator activates "Add Clusters from AKS" on the welcome tab
    And the subscription picker shows "sub-prod" and the operator confirms it
    And the operator selects both "prod-aks" and "staging-aks" in the discovery preview
    And the operator confirms the import
    Then two KubeconfigEntry values are written to the in-memory kubeconfig aggregate
    And the context name for "prod-aks" follows the Azure naming convention:
      """
      rg-prod-prod-aks
      """
    And the exec block for each entry uses command "kubelogin" with args containing:
      """
      [get-token, --environment, AzurePublicCloud]
      """
    And both clusters appear in the cluster strip under the "AKS" provider section
    And no subprocess was invoked during the entire discovery and import sequence

  Scenario: No Azure credentials configured — actionable error is surfaced
    Given no MSAL token is cached for any Azure tenant
    And no service principal environment variables are set
    When the operator activates "Add Clusters from AKS" on the welcome tab
    Then no ARM API call is made
    And an error sheet is presented with the message:
      """
      No Azure credentials found. Sign in via the Azure sign-in flow or configure a
      service principal before retrying.
      """
    And the error sheet contains a "Sign in to Azure" button that initiates the MSAL device-code flow
    And after successful sign-in the operator can retry discovery without reopening the welcome tab

  Scenario: Subscription filter scopes discovery to specified subscriptions only
    Given the operator has a valid MSAL token for a principal with access to two subscriptions:
      "sub-prod" and "sub-dev"
    And "sub-prod" contains AKS cluster "prod-aks"
    And "sub-dev" contains AKS cluster "dev-aks"
    When the operator activates "Add Clusters from AKS" on the welcome tab
    And the subscription picker lists both subscriptions
    And the operator selects only "sub-prod"
    And the operator confirms discovery
    Then the discovery adapter calls the ARM managedClusters endpoint only for subscription "sub-prod"
    And clusters from "sub-dev" are not included in the discovery preview
    And the preview shows only "prod-aks"

  Scenario: Partial import — one cluster has no CA certificate (private cluster), others succeed
    Given the operator has a valid MSAL token
    And subscription "sub-prod" contains three AKS clusters: "public-a", "private-b", "public-c"
    And "private-b" is a private cluster whose ARM response omits the CA certificate field
    When the operator activates "Add Clusters from AKS" on the welcome tab
    And the subscription picker is confirmed with "sub-prod"
    And the operator selects all three clusters in the discovery preview and confirms import
    Then KubeconfigEntry values are written for "public-a" and "public-c"
      with caCertificatePEM populated from the ARM response
    And a KubeconfigEntry is written for "private-b" with an empty caCertificatePEM field
    And a DiscoveryWarning is emitted for "private-b" stating:
      """
      CA certificate unavailable for private cluster private-b.
      Supply the cluster CA certificate manually in cluster settings.
      """
    And the warning is visible in the application notification stream
    And all three clusters appear in the cluster strip and are usable for connection attempts
