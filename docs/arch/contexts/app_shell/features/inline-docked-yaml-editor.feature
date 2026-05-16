# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (inline edit orchestration), Aggregate (DockedEditorPane)
# Context: app_shell
# Related ADRs: ADR-0064 (Inline docked YAML editor pane), ADR-0030 (Integrated multi-format editor), ADR-0057 (Bottom-docked terminal pane with node-debug shell integration)
Feature: Inline docked YAML editor pane

  Background:
    Given the operator has a cluster connected and pinned in the cluster strip
    And the Deployments list is visible in the content area
    And at least one Deployment row named "web-api" in namespace "production" is present

  Scenario: Open docked editor pane from Edit YAML row action
    Given no docked pane is open
    When the operator activates "Edit YAML" from the 3-dot action menu on the "web-api" row
    Then the docked YAML editor pane slides up from the bottom of the content area
    And the pane header breadcrumb reads "Editing kubernetes Deployment web-api in namespace production"
    And line numbers are visible in the editor gutter
    And the editor is in read-only mode
    And the "web-api" row remains highlighted in the list above the pane
    And the "Save" button is disabled
    And the "Discard" button is enabled

  Scenario: Save applies the edited manifest via the ADR-0030 apply path
    Given the docked YAML editor pane is open for Deployment "web-api" in namespace "production"
    And the operator has entered edit mode by pressing "e"
    And the operator changes the value of "spec.replicas" from "2" to "4"
    And the editor has zero error-severity diagnostics
    When the operator clicks "Save"
    Then the ADR-0030 dry-run confirmation modal is presented showing a diff of the change
    And when the operator confirms the mutation
    Then a server-side apply PATCH is issued with fieldManager "com.archanjo.K8sManager"
    And an audit log entry is written for the mutation
    And an outcome toast "Applied successfully" is shown
    And the docked pane closes with a slide-down animation
    And the "web-api" row in the list refreshes to show "replicas: 4"

  Scenario: Cancel with unsaved changes triggers the unsaved-changes guard
    Given the docked YAML editor pane is open for Deployment "web-api" in namespace "production"
    And the operator has entered edit mode
    And the operator has changed "spec.replicas" making the editor dirty
    When the operator clicks "Discard"
    Then a confirmation sheet is presented with the title "Discard changes?"
    And the sheet message references "Deployment/web-api"
    And the sheet presents a "Discard" button and a "Keep Editing" button
    When the operator clicks "Keep Editing"
    Then the sheet is dismissed and the pane remains open with the unsaved edits intact
    When the operator clicks "Discard" again and then clicks "Discard" in the sheet
    Then the docked pane closes with a slide-down animation
    And no mutation is applied to the cluster

  Scenario: Diff overlay toggle shows current YAML versus server state
    Given the docked YAML editor pane is open for Deployment "web-api" in namespace "production"
    And the operator has entered edit mode and changed "spec.replicas" from "2" to "4"
    When the operator clicks the "Diff" toggle in the pane header
    Then the editor splits into a side-by-side diff view
    And the left pane shows the server-state manifest with "replicas: 2"
    And the right pane shows the operator's edited manifest with "replicas: 4"
    And the changed line is highlighted green in the right pane
    And the changed line is highlighted red in the left pane
    And the left pane is read-only
    When the operator clicks the "Diff" toggle again
    Then the diff view collapses and the single-pane editor is restored with the operator's edits intact

  Scenario: Docked YAML editor pane and terminal pane are mutually exclusive
    Given the bottom-docked terminal pane is open with one active PTY session for node "worker-1"
    When the operator activates "Edit YAML" from the 3-dot action menu on the "web-api" row
    Then the terminal pane hides from the content area
    And the docked YAML editor pane slides up in its place
    And an information banner is shown in the editor pane header reading "Terminal sessions are running in the background. Open terminal to resume."
    And the PTY session for "worker-1" remains active in the background
    When the operator closes the YAML editor pane without saving
    And the operator opens the terminal pane via the terminal toolbar button
    Then the terminal pane slides up and the PTY session for "worker-1" is restored and interactive
