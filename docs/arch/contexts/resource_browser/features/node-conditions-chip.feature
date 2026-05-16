# DDD role: BehaviouralSpecification
# DDD Role: ValueObject (StatusChipVariant), ReadModel (NodeConditionsSummary)
# Context: resource_browser
# Related ADRs: ADR-0062 (Status chips and node conditions), ADR-0021 (App shell design system), ADR-0050 (Resource navigation taxonomy)
Feature: Node conditions chip

  Background:
    Given the operator has an active cluster session
    And the operator has navigated to the Nodes list view
    And the list view has finished loading

  Scenario: Ready node shows success chip
    Given a node named "worker-01" with condition "Ready" set to status "True"
    And condition "Ready" has message "kubelet is posting ready status"
    When the Nodes list view renders the row for "worker-01"
    Then the row displays a single status chip with variant "success"
    And the chip label is "Ready"
    And the chip leading icon is "checkmark.circle.fill"

  Scenario: NotReady node shows error chip
    Given a node named "worker-02" with condition "Ready" set to status "False"
    And condition "Ready" has message "container runtime is not responding"
    When the Nodes list view renders the row for "worker-02"
    Then the row displays a single status chip with variant "error"
    And the chip label is "NotReady"
    And the chip leading icon is "xmark.circle.fill"

  Scenario: Scheduling-disabled node shows warning chip
    Given a node named "worker-03" with condition "Ready" set to status "True"
    And the node carries the taint "node.kubernetes.io/unschedulable"
    When the Nodes list view renders the row for "worker-03"
    Then the row displays a single status chip with variant "warning"
    And the chip label is "SchedulingDisabled"
    And the chip leading icon is "exclamationmark.triangle.fill"

  Scenario: Memory-pressure condition overrides ready into error chip
    Given a node named "worker-04" with condition "Ready" set to status "True"
    And the same node has condition "MemoryPressure" set to status "True"
    And condition "MemoryPressure" has message "kubelet has memory pressure"
    When the Nodes list view renders the row for "worker-04"
    Then the row displays a single status chip with variant "error"
    And the chip label is "MemoryPressure"
    And no "Ready" chip is visible in the list row

  Scenario: Tooltip shows underlying condition message
    Given a node named "worker-05" with condition "Ready" set to status "False"
    And condition "Ready" has message "node is not ready: container runtime stopped"
    When the Nodes list view renders the row for "worker-05"
    And the operator hovers the pointer over the status chip for "worker-05"
    Then a tooltip is displayed with the text "node is not ready: container runtime stopped"
    And the chip accessibility hint is "node is not ready: container runtime stopped"
