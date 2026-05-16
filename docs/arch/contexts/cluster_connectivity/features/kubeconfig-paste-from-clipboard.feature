# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (clipboard import orchestration), DomainService (kubeconfig parser + validator)
# Context: cluster_connectivity
# Related ADRs: ADR-0056 (Kubeconfig import from clipboard), ADR-0003 (Kubeconfig read-only), ADR-0054 (Welcome tab)
Feature: Import kubeconfig from clipboard

  As an operator on macOS
  I want to paste a kubeconfig YAML blob directly from my clipboard
  So that I can connect to a cluster without saving a temporary file to disk

  Background:
    Given the application is running with no in-progress import sheet open
    And the per-cluster store contains no existing cluster entries

  Scenario: Valid kubeconfig is pasted and successfully imported
    Given the clipboard contains a well-formed kubeconfig YAML with 2 clusters and 2 contexts
    And both context entries reference existing cluster and user entries
    And both cluster server URLs parse as valid https URLs
    When the operator activates the "Add kubeconfig from clipboard" action
    Then the import sheet opens
    And the sheet shows an indeterminate progress indicator while parsing
    And after parsing completes the sheet displays "2 clusters found"
    And the sheet displays "2 contexts found"
    And each cluster row shows a detected provider hint derived from the exec-block command
    And the "Import" button is enabled
    When the operator presses "Import"
    Then the sheet is dismissed
    And both clusters appear in the cluster strip
    And both clusters appear in the sidebar tree under their respective provider sections
    And a toast notification reads "2 cluster(s) added from clipboard"
    And no kubeconfig material is written to the filesystem during or after the import

  Scenario: Clipboard is empty when the import action is activated
    Given the clipboard contains no plain-text value
    When the operator activates the "Add kubeconfig from clipboard" action
    Then the import sheet opens
    And the sheet displays the message "Clipboard is empty. Copy a kubeconfig YAML and try again."
    And the "Import" button is disabled
    And the "Paste from Clipboard" button is visible and keyboard-focusable
    When the operator copies a valid kubeconfig YAML to the clipboard
    And the operator presses "Paste from Clipboard"
    Then the sheet re-reads the clipboard and reruns parse and validation
    And the sheet transitions to the validation-passed state

  Scenario: Clipboard contains non-YAML text and surfaces a line-number error
    Given the clipboard contains the plain-text string "not yaml: [this is broken: }"
    When the operator activates the "Add kubeconfig from clipboard" action
    Then the import sheet opens
    And the sheet renders the pasted text in a read-only view with a line-number gutter
    And at least one error marker is visible identifying the line of the parse failure
    And the error description is plain English and contains no raw token or certificate data
    And the "Import" button is disabled
    And the "Cancel" button is visible and dismisses the sheet when activated

  Scenario: Pasted kubeconfig conflicts with an existing cluster and operator is offered rename or replace
    Given the per-cluster store already contains a cluster with context name "production"
    And the clipboard contains a well-formed kubeconfig YAML with a context named "production"
    When the operator activates the "Add kubeconfig from clipboard" action
    And the import sheet completes validation successfully
    Then the summary table shows a conflict warning badge next to the "production" context
    And the sheet offers three resolution options: "Rename and add", "Replace existing", and "Skip"
    When the operator selects "Rename and add"
    Then the sheet proposes the context name "production-1" in an editable field
    When the operator confirms without editing the proposed name and presses "Import"
    Then the sheet is dismissed
    And a cluster with context name "production-1" is added to the per-cluster store
    And the original "production" cluster entry remains unchanged in the per-cluster store
