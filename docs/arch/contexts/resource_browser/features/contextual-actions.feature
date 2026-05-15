# DDD Role: DomainService (ResourceBrowserService, ShortcutDispatchService), ValueObject (ShortcutBinding)
# Context: resource_browser
# Related ADRs: ADR-0023 (keyboard shortcut vocabulary and whenContext predicate), ADR-0012 (mutating operations policy)
Feature: Contextual keyboard shortcuts per resource kind

  Background:
    Given the resource browser list has keyboard focus
    And the focused element is not a text input field and not an embedded terminal pane

  Scenario: Pod selected — l key opens log stream
    Given a Pod resource row is selected
    When the operator presses the l key
    Then the log stream panel opens for the selected pod
    And the panel title includes the pod name and namespace
    And the stream begins tailing from the most recent log lines

  Scenario: Pod selected — s key opens exec shell
    Given a Pod resource row is selected
    When the operator presses the s key
    Then a container selection prompt appears if the pod has more than one container
    And selecting a container opens a terminal session panel via the terminal_session bounded context
    And the session is labelled with the pod name and selected container name

  Scenario: Pod selected — d key shows inline describe output
    Given a Pod resource row is selected
    When the operator presses the d key
    Then the detail pane opens at Layer 2
    And a describe view renders conditions, events, owner references, resource requests and limits, and volume mounts
    And the describe view does not issue a mutation command

  Scenario: Deployment selected — s key opens scale dialog
    Given a Deployment resource row is selected
    When the operator presses the s key
    Then a scale dialog sheet is presented showing the current replica count
    And the operator can increment or decrement the replica count
    And confirming the dialog constructs a ScaleReplicas mutation command subject to the ADR-0012 confirmation policy

  Scenario: ConfigMap selected — e key opens YAML editor
    Given a ConfigMap resource row is selected
    When the operator presses the e key
    Then the YAML editor opens at Layer 3 with the live server manifest loaded
    And saving the editor constructs an ApplyYAML mutation command subject to the ADR-0012 diff preview and confirmation policy
    And pressing Escape returns to Layer 2 without constructing any command

  Scenario: CRD instance selected — e key opens schema-aware YAML editor
    Given a custom resource instance row is selected where the resource kind has a CRD schema registered in the KindCatalogue
    When the operator presses the e key
    Then the YAML editor opens at Layer 3 with the live server manifest loaded
    And the editor performs inline schema validation against the CRD OpenAPI schema
    And schema violations are surfaced as inline annotations before the operator can save
    And saving constructs an ApplyYAML mutation command subject to the ADR-0012 confirmation policy

  Scenario: Service selected — u key shows endpoints and workload owner
    Given a Service resource row is selected
    When the operator presses the u key
    Then the detail pane opens a used-by panel
    And the panel lists all Endpoints and EndpointSlices backing the service
    And the panel identifies the owning workload by following owner references to Deployment, StatefulSet, or DaemonSet
    And the panel does not issue any mutation command
