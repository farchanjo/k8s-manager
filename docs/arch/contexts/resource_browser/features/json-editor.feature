# DDD role: BehaviouralSpecification
Feature: JSON editor with syntax highlighting and schema validation
  As an operator of K8sManager
  I want to edit JSON content within the integrated editor
  So that I can benefit from syntax highlighting, schema validation, and safe format-on-save

  Background:
    Given the operator is connected to a Kubernetes cluster named "staging"
    And the integrated editor (ADR-0030) is available with sourceFormat "json"

  # ---------------------------------------------------------------------------
  Scenario: JSON content is displayed with syntax highlighting
    Given a ConfigMap named "feature-flags" has a data key "config.json" containing:
      """
      {
        "featureA": true,
        "maxRetries": 5,
        "endpoint": "https://api.example.com"
      }
      """
    When the operator opens "config.json" in the JSON editor
    Then the editor displays the JSON content with tree-sitter-json syntax highlighting
    And string values are coloured with the "string" token theme colour
    And boolean values are coloured with the "boolean" token theme colour
    And numeric values are coloured with the "number" token theme colour
    And object keys are coloured with the "property" token theme colour
    And the gutter shows line numbers for every line

  # ---------------------------------------------------------------------------
  Scenario: JSON Schema validation marks invalid value type as error
    Given a ConfigMap "job-config" has a data key "settings.json" associated with a JSON Schema
    And the schema requires "timeout" to be of type integer
    When the operator changes "timeout" from 30 to "thirty" (a string value) in the editor
    And 150 milliseconds elapse after the last keystroke
    Then a diagnostic marker appears in the gutter on the "timeout" line
    And the diagnostic severity is "error"
    And the diagnostic source is "json-schema"
    And the diagnostic message contains "expected integer"
    And the Apply button is disabled while any "error" diagnostic is present

  # ---------------------------------------------------------------------------
  Scenario: Pretty-print on save normalises JSON indentation
    Given the editor buffer contains minified JSON:
      """
      {"apiVersion":"v1","kind":"ConfigMap","metadata":{"name":"compact","namespace":"default"},"data":{"key":"value"}}
      """
    When the operator presses Cmd+S
    Then JSONSerialization pretty-prints the buffer with 2-space indentation
    And the saved content spans multiple lines with proper nesting
    And "apiVersion" appears on its own line indented at root level
    And "metadata" block contains "name" and "namespace" each on separate lines
    And a transient "Formatted" indicator appears in the editor toolbar

  # ---------------------------------------------------------------------------
  Scenario: Editing ConfigMap data.json field and applying via dry-run
    Given a ConfigMap named "runtime-config" is open in the JSON editor in editing mode
    And the buffer contains a JSON object with key "logLevel" set to "info"
    When the operator changes "logLevel" from "info" to "debug"
    And 600 milliseconds elapse after the last keystroke
    Then a dry-run PATCH is sent to the Kubernetes API with dryRun=All
    And editorState transitions to "dryRunComplete" with a non-empty diffPreview
    And the diff preview shows '- "logLevel": "info"' and '+ "logLevel": "debug"'
    When the operator clicks Apply and confirms in the modal
    Then the mutation routes through the ADR-0012 confirmation guard
    And a #MutationAuditEntry is written with verb "patch" and outcome "succeeded"

  # ---------------------------------------------------------------------------
  Scenario: Invalid JSON syntax marks the error inline and disables Apply
    Given the operator is editing a JSON document in the editor
    When the operator types an unmatched opening brace "{{" on line 3
    And 150 milliseconds elapse after the last keystroke
    Then a diagnostic marker appears in the gutter on line 3
    And the diagnostic severity is "error"
    And the diagnostic source is "json-parser"
    And the diagnostic message contains "unexpected token" or "parse error"
    And the Apply button is disabled
    And the dry-run service does not send a PATCH request while error diagnostics are present
    When the operator corrects the syntax error
    Then the error diagnostic clears within 150 milliseconds of the fix
    And the Apply button re-enables (assuming no remaining error diagnostics)
