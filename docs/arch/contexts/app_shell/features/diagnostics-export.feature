Feature: Diagnostics bundle export
  As an operator or support engineer working with K8sManager
  I want to export a self-contained diagnostics bundle as a zip file
  So that I can share reproducible, redacted evidence of application behaviour without leaking credentials

  Background:
    Given K8sManager is running
    And the SelfMonitoringSampler has been collecting metrics for at least 10 minutes
    And exportEnabled is true in #SelfMonitoringState
    And Settings → Diagnostics is open

  # ---------------------------------------------------------------------------
  # Scenario 1 — Export bundle is written to the canonical exports directory
  # ---------------------------------------------------------------------------

  Scenario: Export bundle is created in the configured exports directory
    When the operator clicks "Export diagnostics bundle"
    Then DiagnosticsBundleExporter writes a zip file to
         "~/.config/k8smanager/exports/diagnostics-<yyyy-mm-dd-HH-MM-SS>.zip"
    And the timestamp in the filename reflects the moment the export was triggered
    And the zip file is readable and contains a valid central directory
    And the operator sees a success notification with the full path to the bundle

  # ---------------------------------------------------------------------------
  # Scenario 2 — Bundle contains last 24 hours of metrics and redacted logs
  # ---------------------------------------------------------------------------

  Scenario: Export bundle includes last 24 hours of metric samples and sanitized logs
    Given metrics have been collected for at least 24 hours and persisted to SQLite
    When the operator triggers an export
    Then the bundle zip contains "metrics/self-metrics-24h.json"
    And each line of "metrics/self-metrics-24h.json" is a valid JSON object
         conforming to the #SelfMetricSample schema
    And the oldest sample timestamp is no more than 24 hours before the export timestamp
    And the bundle zip contains at least one file under "logs/" with a ".redacted" suffix
    And "bundle-manifest.json" at the zip root is a valid #DiagnosticsBundle record
    And the sampleCount field in the manifest matches the actual number of JSON lines
    And the redactionApplied field in the manifest is true

  # ---------------------------------------------------------------------------
  # Scenario 3 — Credential material does not appear in the exported bundle
  # ---------------------------------------------------------------------------

  Scenario: Bearer tokens and kubeconfig paths are scrubbed from log files
    Given the application logs contain entries with bearer tokens matching
          "Bearer [A-Za-z0-9._-]{20,}"
    And the application logs contain kubeconfig paths matching
          "/Users/<username>/.kube/config"
    When the operator triggers an export
    Then the redacted log file in the bundle contains no substring matching
         the pattern "Bearer [A-Za-z0-9._-]{20,}"
    And the redacted log file contains no substring matching
         "/Users/[^/]+/.kube"
    And every redacted bearer token is replaced with the literal "Bearer [REDACTED]"
    And every redacted path is replaced with the literal "[REDACTED_PATH]"

  # ---------------------------------------------------------------------------
  # Scenario 4 — Bundle filename uses the canonical date-time format
  # ---------------------------------------------------------------------------

  Scenario: Bundle filename matches the canonical pattern
    When the operator triggers an export at 2026-05-15 14:32:07 local time
    Then the created zip filename is "diagnostics-2026-05-15-14-32-07.zip"
    And the file resides at
         "~/.config/k8smanager/exports/diagnostics-2026-05-15-14-32-07.zip"
    When the operator triggers a second export within the same second
    Then the second bundle has a distinct filename (suffix incremented or milliseconds appended)
    And neither bundle overwrites the other

  # ---------------------------------------------------------------------------
  # Scenario 5 — Failed redaction aborts the export and no partial bundle is written
  # ---------------------------------------------------------------------------

  Scenario: Log redaction failure aborts the export with no partial output
    Given the log redactor encounters an unrecoverable error while processing a log file
         (for example, a file read permission error on a rotated log)
    When the operator triggers an export
    Then DiagnosticsBundleExporter does not write any zip file to the exports directory
    And no partial zip or temporary file remains on disk after the failure
    And the operator sees an error notification: "Export failed: log redaction could not complete"
    And the error details are written to the application log at level ERROR
    And the #DiagnosticsBundle record is never created for the failed attempt

  # ---------------------------------------------------------------------------
  # Scenario 6 — Export with fewer than 24 hours of data succeeds with partial history
  # ---------------------------------------------------------------------------

  Scenario: Export succeeds when fewer than 24 hours of metrics are available
    Given the application has only been running for 2 hours
    And metrics from the last 2 hours are available in SQLite
    When the operator triggers an export
    Then the bundle is created successfully
    And "metrics/self-metrics-24h.json" contains only samples from the available 2-hour window
    And the sampleCount field in the manifest accurately reflects the number of samples present
    And the operator sees a success notification indicating the actual time range covered
