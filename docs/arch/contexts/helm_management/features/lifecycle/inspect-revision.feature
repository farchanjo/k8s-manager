# DDD role: BehaviouralSpecification
# Bounded context: helm_management
# References: ADR-0015
# CUE schema: contexts/helm_management/schemas/release_history_entry.cue

Feature: Inspect a specific Helm release revision
  As an operator
  I want to open a specific historical revision of a Helm release and view its rendered manifests
  So that I can understand what was deployed at a past revision without using the helm CLI

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And the helm_management context shows release "nginx" with revisions 1 through 5

  @happy @lifecycle
  Scenario: Opening revision 3 decodes and renders its manifests
    When the operator selects revision 3 in the history view for "nginx"
    Then the adapter retrieves the Secret "sh.helm.release.v1.nginx.v3" from the cluster
    And decodes "data.release" via base64-decode → gunzip → JSON-decode
    And the decoded HelmReleasePayload.manifest string is parsed as multi-document YAML
    And the manifests are displayed in the resource viewer as individual YAML documents
    And the chart metadata (name, version, appVersion) is shown in the revision header

  @failure @lifecycle
  Scenario: Revision Secret missing from cluster — graceful error
    Given the Secret "sh.helm.release.v1.nginx.v2" has been manually deleted from the cluster
    When the operator selects revision 2 in the history view
    Then the adapter issues a GET for the Secret and receives HTTP 404
    And the UI shows "Revision 2 is no longer available — it may have been deleted"
    And no crash or unhandled error occurs

  @failure @lifecycle
  Scenario: Corrupt gzip payload triggers decoder invariant check
    Given the Secret for revision 4 has a "data.release" field that is not valid gzip
    When the adapter attempts to gunzip the base64-decoded bytes
    Then the gunzip operation throws a decompression error
    And the release_decoder_invariants policy logs the invariant violation
    And the UI shows "Revision 4 could not be decoded — the Secret may be corrupted"

  @happy @lifecycle
  Scenario: Chart CRD manifests embedded in the revision are listed separately
    Given revision 5 of "prometheus-stack" contains CRD manifests in the chart's crds/ directory
    When the operator opens revision 5
    Then the manifests viewer shows a "CRDs" section alongside the main manifests
    And each CRD manifest is displayed as its own YAML document with kind "CustomResourceDefinition"
