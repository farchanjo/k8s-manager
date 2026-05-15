# DDD role: BehaviouralSpecification
# Bounded context: helm_management
# References: ADR-0015
# CUE schema: contexts/helm_management/schemas/release.cue

Feature: List Helm 3 releases by reading helm.sh/release.v1 Secrets
  As an operator
  I want to see all Helm releases deployed in a cluster namespace
  So that I can inspect what is running without leaving K8sManager

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And the resource browser is showing namespace "production"

  @happy @lifecycle
  Scenario: Helm releases are discovered by listing Secrets with owner=helm label
    When the helm_management context requests releases for namespace "production"
    Then the adapter issues a LIST request to "/api/v1/namespaces/production/secrets?labelSelector=owner%3Dhelm"
    And the response includes Secrets of type "helm.sh/release.v1"
    And the adapter base64-decodes each Secret's "data.release" field
    And gunzips the decoded bytes using the gzip algorithm
    And JSON-decodes the result into a HelmReleasePayload struct
    And the decoded releases are returned as a list of #Release aggregates
    And the UI displays each release with its name, namespace, version, and status

  @failure @lifecycle
  Scenario: Non-secret Helm driver detected — degradation banner shown
    Given no Secrets with "owner=helm" label exist in "production"
    But Deployments in "production" carry the annotation "app.kubernetes.io/managed-by=Helm"
    When the helm_management context requests releases for "production"
    Then the adapter finds zero "helm.sh/release.v1" Secrets
    And the UI displays a degradation banner: "Helm releases not visible — the cluster may be using a non-secret Helm driver"
    And no error is thrown and no crash occurs

  @happy @lifecycle
  Scenario: Multiple revisions of the same release are grouped by name
    Given the cluster has Secrets for release "nginx" at revisions 3, 4, and 5
    And revision 5 has status "deployed" and revisions 3 and 4 have status "superseded"
    When the helm_management context groups revisions by (name, namespace)
    Then the release list shows "nginx" as a single entry at revision 5 with status "deployed"
    And the history view for "nginx" shows revisions 3, 4, and 5

  @security @lifecycle
  Scenario: Release Secret containing PEM-encoded certificate is rejected by the decoder invariants
    Given a Helm Secret's rendered manifest YAML contains a PEM-encoded certificate block "-----BEGIN CERTIFICATE-----"
    When the release_decoder_invariants Rego policy is evaluated
    Then the policy denies materialising a #Release aggregate from that Secret
    And the UI shows a warning: "Release skipped — manifest contains credential material"
    And no certificate data is displayed or stored
