# DDD role: BehaviouralSpecification
@adr-0052 @adr-0013 @adr-0050
Feature: Resource kind catalog CRD discovery and sidebar refresh
  As a Kubernetes operator working with CRD-heavy stacks
  I want custom resources to appear in the sidebar automatically when CRDs are installed
  So that I can navigate to Argo, Flux, Cert Manager, and other custom resources
  Without disconnecting and reconnecting the cluster session

  Background:
    Given the application is running on macOS 14 or later
    And the operator has an active session for cluster "prod-aks"
    And the ResourceDescriptorRegistry has completed the initial discovery flow

  Scenario: Newly installed CRD group appears in sidebar without reconnect
    Given the "Custom Resources" sidebar section is visible
    And no CRDs are installed for API group "argoproj.io"
    When the Argo CD CRDs are installed on the cluster
    And the Kubernetes API emits ADDED watch events for the new CustomResourceDefinitions
    Then the "Custom Resources" sidebar section shows an "argoproj.io" group
    And the group contains "Application", "ApplicationSet", "Workflow" kinds
    And no cluster reconnect was required
    And a CRDCatalogUpdated domain event is emitted with addedGroups=["argoproj.io"]

  Scenario: CRD kind list view renders additionalPrinterColumns
    Given the CRD "Application" in group "argoproj.io" has additionalPrinterColumns:
      - name: "Sync Status", jsonPath: ".status.sync.status", type: "string"
      - name: "Health", jsonPath: ".status.health.status", type: "string"
    When the operator opens a "Application" tab for namespace "argocd"
    Then the list view shows columns: Name, Namespace, Age, Sync Status, Health
    And the "Sync Status" column values are extracted from ".status.sync.status"
    And the "Health" column values are extracted from ".status.health.status"

  Scenario: CRD discovery groups kinds by API group in the sidebar
    Given CRDs are installed for groups "argoproj.io", "cert-manager.io", and "fluxcd.io"
    When the operator expands the "Custom Resources" section
    Then the section shows three collapsible group headers: "argoproj.io", "cert-manager.io", "fluxcd.io"
    And each group is sorted alphabetically by API group name
    And kinds within each group are sorted alphabetically

  Scenario: CRD group with zero instances shows count badge of 0 rather than hiding
    Given "cert-manager.io" group is discovered with kinds "Certificate", "Issuer"
    And no Certificate or Issuer instances exist in the active namespace
    When the operator expands the "cert-manager.io" group
    Then both "Certificate" and "Issuer" appear with a count badge of "0"
    And the group is not hidden despite having zero instances

  Scenario: Removed CRD group disappears from sidebar on next watch event
    Given the "custom.example.io" CRD group is shown in the sidebar with 2 kinds
    When all CRDs in the "custom.example.io" group are deleted from the cluster
    And the Kubernetes API emits DELETED watch events for those CustomResourceDefinitions
    Then the "custom.example.io" group is removed from the "Custom Resources" sidebar section
    And a CRDCatalogUpdated event is emitted with removedGroups=["custom.example.io"]
    And any open tabs for "custom.example.io" kinds display a "kind unavailable" banner

  Scenario: Schema-guided rendering for a CRD with embedded OpenAPI v3 schema
    Given the CRD "Certificate" in "cert-manager.io" has an embedded OpenAPI v3 schema
    And the schema declares top-level properties: dnsNames (array), issuerRef (object), secretName (string)
    When the operator opens a Certificate resource detail view
    Then the properties grid shows rows for: dnsNames, issuerRef, secretName
    And each row shows the schema title or property key as the label
    And the issuerRef row renders as an expandable sub-grid for nested object fields

  Scenario: Fallback rendering when CRD has no embedded schema
    Given the CRD "MyResource" has x-kubernetes-preserve-unknown-fields=true at root
    And therefore no typed OpenAPI v3 schema is available
    When the operator opens a MyResource detail view
    Then the YAML tab is shown by default
    And the properties grid tab shows only metadata fields
    And no schema-validation errors appear in the editor

  Scenario: Multi-version CRD shows version picker in detail drawer
    Given the CRD "Application" in "argoproj.io" has versions: "v1alpha1", "v1beta1"
    And the preferred (storage) version is "v1beta1"
    When the operator opens an Application detail view
    Then the detail drawer header shows a version chip displaying "v1beta1"
    When the operator clicks the version chip
    Then a dropdown shows both "v1alpha1" and "v1beta1"
    When the operator selects "v1alpha1"
    Then the detail view re-fetches the resource using API version "v1alpha1"
    And the selected version is stored in the tab's selectedVersion field

  Scenario: CRD discovery runs in parallel with standard kind registration
    Given the cluster connection is established
    When the ResourceDescriptorRegistry executes the 5-step discovery flow
    Then steps 1 through 5 are executed concurrently in a TaskGroup
    And the standard 51 kinds are registered immediately on session open
    And CRD kinds are added to the registry as each CustomResourceDefinition is processed
    And the sidebar refreshes incrementally as each CRD group is completed
