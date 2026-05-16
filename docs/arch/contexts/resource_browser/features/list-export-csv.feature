# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (export orchestration), DomainService (CSV serialiser, YAML serialiser, redaction policy)
# Context: resource_browser
# Related ADRs: ADR-0060 (Resource list export), ADR-0050 (Resource navigation taxonomy), ADR-0047 (Audit chain HMAC keychain)
Feature: Resource list export to CSV and per-row YAML

  Background:
    Given the operator has an active cluster session
    And the operator has opened the Pods list for namespace "default"
    And the list contains 12 Pod rows matching no active search query

  Scenario: CSV export of the visible filtered list
    Given the list item count badge shows "12 items"
    And no search query is active
    When the operator activates the download icon next to the item count badge
    Then an NSSavePanel is presented with filename "Pod-<ClusterDisplayName>-<Timestamp>.csv"
    And the proposed save directory is ~/Downloads
    When the operator confirms the save location
    Then a UTF-8 CSV file is written to the chosen path
    And the file contains a header row with columns "name,namespace,status,ready,restarts,node,age"
    And the file contains exactly 12 data rows in the same order as the visible list
    And an audit log entry with action "export-list-csv" and row-count 12 is signed and persisted

  Scenario: CSV export honours the active namespace filter and search query
    Given the operator has applied a search query matching 4 of the 12 Pod rows
    And the item count badge shows "4 items"
    When the operator activates the download icon next to the item count badge
    Then an NSSavePanel is presented
    When the operator confirms the save location
    Then the CSV file contains exactly 4 data rows
    And the 4 rows correspond to the filtered visible rows in the order they appear in the list
    And the CSV header comment includes a "Last refreshed <timestamp>" annotation

  Scenario: CSV export honours the active sort order
    Given the operator has sorted the list by the "restarts" column in descending order
    When the operator activates the download icon next to the item count badge
    And confirms the save location
    Then the CSV rows are ordered by descending restart count matching the visible list order
    And the first CSV data row corresponds to the Pod with the highest restart count in the list

  Scenario: Per-row YAML export via 3-dot action menu
    Given the operator opens the 3-dot context menu for a Deployment row named "my-api" in namespace "default"
    When the operator selects "Save YAML"
    Then a fresh manifest is fetched from the Kubernetes API for Deployment "my-api" in namespace "default"
    And an NSSavePanel is presented with filename "Deployment-default-my-api-<Timestamp>.yaml"
    When the operator confirms the save location
    Then a YAML file is written beginning with the document marker "---"
    And the file contains a valid Kubernetes Deployment manifest for "my-api"
    And an audit log entry with action "export-resource-yaml" and redacted false is signed and persisted

  Scenario: Secret YAML export prompts redaction confirmation before NSSavePanel
    Given the operator opens the 3-dot context menu for a Secret row named "db-password" in namespace "default"
    When the operator selects "Save YAML"
    Then a redaction confirmation dialog is presented before the NSSavePanel
    And the dialog body states that Secret data values will be replaced with hash placeholders
    And the checkbox "Export unredacted Secret data" is present and unchecked by default
    When the operator leaves the checkbox unchecked and confirms
    Then an NSSavePanel is presented with filename "Secret-default-db-password-<Timestamp>.yaml"
    When the operator confirms the save location
    Then the written YAML contains "data:" entries where each value matches the pattern "[redacted:sha256:<8hexchars>]"
    And the "stringData" field is absent from the written YAML
    And an audit log entry with action "export-resource-yaml" and redacted true is signed and persisted

  Scenario: Export records an audit entry for each operation
    Given the operator exports the visible Pod list as CSV and saves it successfully
    And the operator exports a Deployment YAML via the row action menu and saves it successfully
    When the operator opens the audit log view
    Then the audit log contains one entry with action "export-list-csv" for the Pod CSV export
    And the audit log contains one entry with action "export-resource-yaml" for the Deployment YAML export
    And both entries carry a valid HMAC signature per ADR-0047
    And both entries record the destination file path chosen by the operator
