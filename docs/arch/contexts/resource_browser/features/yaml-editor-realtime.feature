# DDD role: BehaviouralSpecification
Feature: YAML editor real-time validation and dry-run apply
  As an operator of K8sManager
  I want to edit Kubernetes resource manifests in an integrated YAML editor
  So that I can see live validation feedback, a dry-run diff preview, and apply changes safely

  Background:
    Given the operator is connected to a Kubernetes cluster named "prod-east"
    And the resource browser is open showing the "default" namespace
    And the integrated editor (ADR-0030) is available

  # ---------------------------------------------------------------------------
  Scenario: Open a Pod manifest in the YAML editor in read-only mode
    Given a Pod named "web-0" exists in namespace "default"
    When the operator selects "web-0" in the resource browser and presses "e"
    Then the integrated editor opens with sourceFormat "yaml"
    And the editor displays the live server manifest for "web-0"
    And the editorState is "idle" initially for one rendering frame
    And the editorState transitions to "editing" within 200 milliseconds
    And the editor toolbar shows an "Edit" button in active state
    And the gutter shows line numbers for every line
    And no diagnostic markers appear in the gutter (manifest is valid)

  # ---------------------------------------------------------------------------
  Scenario: Changing replicas in a Deployment triggers a debounced dry-run
    Given a Deployment named "api-server" with spec.replicas 3 is open in the editor in editing mode
    When the operator changes "replicas: 3" to "replicas: 5" in the editor buffer
    Then within 100 milliseconds a validation pass runs (editorState briefly "validating")
    And the editorState returns to "editing" with zero diagnostics
    And within 600 milliseconds (500 ms debounce elapsed) the editorState transitions to "dryRunning"
    And a PATCH request with dryRun=All is sent to the Kubernetes API
    And the editorState transitions to "dryRunComplete" with a non-empty diffPreview
    And the diff preview pane shows "- replicas: 3" in red and "+ replicas: 5" in green

  # ---------------------------------------------------------------------------
  Scenario: Diff preview shows added and removed fields after manifest edit
    Given a ConfigMap named "app-config" is open in the editor in editing mode
    And the original manifest has a key "data.env" with value "production"
    When the operator adds a new key "data.region: us-east-1" below "data.env"
    And the operator removes "data.env: production" from the buffer
    And 600 milliseconds elapse after the last keystroke
    Then the diff preview pane is visible
    And the diff preview shows "+ data.region: us-east-1" as an added line
    And the diff preview shows "- data.env: production" as a removed line
    And all other lines appear as context (collapsed if more than 3 consecutive)

  # ---------------------------------------------------------------------------
  Scenario: Schema validation marks an unknown field as a warning
    Given a Deployment named "worker" is open in the editor in editing mode
    And the operator types "  unknownField: true" under "spec:" in the buffer
    When 150 milliseconds elapse after the last keystroke
    Then a diagnostic marker appears in the gutter on the line containing "unknownField"
    And the diagnostic severity is "warning"
    And the diagnostic source is "k8s-schema"
    And the diagnostic message contains "unknown field"
    And the diagnostics panel shows one warning entry with line reference

  # ---------------------------------------------------------------------------
  Scenario: Format on save (Cmd+S) reorganises YAML keys alphabetically
    Given a ConfigMap named "settings" is open in the editor in editing mode
    And the buffer contains:
      """
      apiVersion: v1
      kind: ConfigMap
      data:
        zebra: last
        alpha: first
      metadata:
        name: settings
        namespace: default
      """
    When the operator presses Cmd+S
    Then the yamlfmt formatter runs on the buffer
    And the saved content has keys sorted alphabetically at each level
    And "alpha: first" appears before "zebra: last" in the data block
    And "metadata:" appears before "data:" at the document root
    And no dry-run is triggered by the format-only save
    And the editor shows a transient "Formatted" indicator in the toolbar

  # ---------------------------------------------------------------------------
  Scenario: Multi-cursor edit selects next occurrence with Cmd+D
    Given a Deployment named "cache" is open in the editor in editing mode
    And the buffer contains the string "app: cache" on lines 8, 14, and 22
    When the operator places the cursor on line 8 within the token "cache"
    And the operator presses Cmd+D once
    Then a second cursor appears on line 14 at the same token "cache"
    When the operator presses Cmd+D again
    Then a third cursor appears on line 22 at the same token "cache"
    When the operator types "cache-v2"
    Then all three occurrences are replaced with "cache-v2" simultaneously
    And the undo stack records this as a single undoable action

  # ---------------------------------------------------------------------------
  Scenario: Draft auto-save persists when operator closes without applying
    Given a Secret named "db-creds" is open in the editor in editing mode
    And the operator has changed "data.DB_PASS" to a new base64 value
    And isDirty is true
    When the operator closes the editor window without clicking Apply
    Then within 5 seconds a #Draft row is written to the editor_drafts table
    And the draft row has sourceFormat "yaml"
    And the draft row has autoSaved true
    And the draft content equals the last buffer content before close
    When the operator reopens "db-creds" in the editor on the next session
    Then a dismissible banner appears: "Unsaved draft from <timestamp> — Restore / Discard"
    And clicking Restore loads the draft content into the editor buffer

  # ---------------------------------------------------------------------------
  Scenario: Apply pipeline routes through ADR-0012 mutation guard chain
    Given a Deployment named "frontend" is open in the editor in editing mode
    And the operator has changed spec.replicas from 2 to 4
    And editorState is "dryRunComplete" with a non-empty diffPreview and no conflicts
    When the operator clicks the "Apply" button
    Then the confirmation modal appears showing the diff preview
    And the modal displays the mutation command type "ApplyYAML"
    When the operator confirms
    Then editorState transitions to "applying"
    And a PATCH request with fieldManager=com.archanjo.K8sManager is sent (no dryRun)
    And on success editorState transitions to "applied" with outcome "succeeded"
    And a #MutationAuditEntry row is written to cluster_mutation_audit
    And an outcome toast appears: "Deployment frontend updated successfully"
    And editorState transitions to "idle" (editor returns to read-only mode)
