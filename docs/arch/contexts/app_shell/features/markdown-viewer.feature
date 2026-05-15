Feature: Markdown viewer with side-by-side live preview
  As an operator of K8sManager
  I want to view and edit Markdown content with a live rendered preview
  So that I can read documentation embedded in cluster resources without leaving the application

  Background:
    Given the operator is connected to a Kubernetes cluster named "dev"
    And the integrated editor (ADR-0030) is available with sourceFormat "markdown"

  # ---------------------------------------------------------------------------
  Scenario: Open a README from a Helm chart ConfigMap
    Given a ConfigMap named "my-chart-readme" exists in namespace "helm-releases"
    And the ConfigMap has a data key "README.md" containing Markdown content
    When the operator opens "README.md" in the Markdown viewer
    Then the editor opens in sourceFormat "markdown"
    And the left pane shows the raw Markdown source with tree-sitter-markdown highlighting
    And the right pane shows the rendered Markdown preview
    And the preview renders headings, paragraphs, and lists correctly
    And no Apply or dry-run controls are visible (Markdown is not a Kubernetes manifest)

  # ---------------------------------------------------------------------------
  Scenario: Preview pane updates side-by-side while operator edits
    Given a Markdown document is open in the editor in editing mode
    And the left pane shows "# Hello World" on line 1
    When the operator changes "Hello World" to "Hello K8sManager"
    And 200 milliseconds elapse after the last keystroke (preview debounce)
    Then the right preview pane updates to render "Hello K8sManager" as a level-1 heading
    And the update happens without a full preview reload (incremental render)
    And the editor cursor position is preserved in the left pane

  # ---------------------------------------------------------------------------
  Scenario: Live update renders code blocks with syntax highlighting
    Given a Markdown document is open in editing mode
    When the operator types a fenced code block:
      """
      ```yaml
      apiVersion: apps/v1
      kind: Deployment
      ```
      """
    And 200 milliseconds elapse after the last keystroke
    Then the preview pane renders the code block with YAML syntax highlighting
    And the fence info string "yaml" is used to select the tree-sitter grammar
    And the rendered code block is visually distinct from surrounding prose

  # ---------------------------------------------------------------------------
  Scenario: External links in the preview open with a confirmation dialog
    Given a Markdown document contains a link "[Docs](https://kubernetes.io/docs)"
    When the preview pane renders the document
    And the operator clicks the rendered link in the preview pane
    Then a confirmation dialog appears with title "Open external link?"
    And the dialog body shows the target URL "https://kubernetes.io/docs"
    And the dialog offers "Cancel" and "Open in Browser" actions
    When the operator clicks "Open in Browser"
    Then NSWorkspace.open is called with "https://kubernetes.io/docs"
    And the K8sManager application retains focus

  # ---------------------------------------------------------------------------
  Scenario: Closing a dirty Markdown document triggers draft auto-save
    Given a Markdown document "notes.md" is open in editing mode
    And the operator has added several lines to the document (isDirty is true)
    When the operator closes the editor without saving
    Then a #Draft row is written to the editor_drafts table within 5 seconds
    And the draft has sourceFormat "markdown"
    And the draft has autoSaved true
    And on next open of "notes.md" a banner offers "Unsaved draft from <timestamp> — Restore / Discard"
