# DDD role: BehaviouralSpecification
Feature: Node debug session
  As a cluster operator using K8sManager
  I want to open a privileged debug shell on a Kubernetes node
  So that I can inspect host-level networking, processes, and storage
  without SSH access to the underlying VM

  Background:
    Given a kubeconfig context "prod-cluster" is active
    And the cluster is reachable and responds to API requests
    And the operator has RBAC permissions to create Pods in the "default" namespace
    And the operator has RBAC permissions to exec into Pods in the "default" namespace

  Scenario: Create debug Pod requires mutating confirmation per ADR-0012
    Given a Node "node-worker-01" exists in the cluster and is in "Ready" state
    When the operator requests a debug session on Node "node-worker-01"
    Then the UI presents a mutating-operation confirmation dialog
    And the dialog states that a privileged Pod will be created on "node-worker-01"
    And the dialog shows the debug image "nicolaka/netshoot:v0.13"
    And the dialog warns that the Pod will have hostNetwork and hostPID enabled
    When the operator confirms the operation
    Then a MutationAuditEntry is recorded for the Pod creation per ADR-0012
    And the KubernetesDebugCreatorPort creates a Pod named matching pattern
      "node-debugger-node-worker-01-[0-9a-f]{8}" in namespace "default"
    And the Pod spec has hostNetwork: true, hostPID: true, and privileged: true
    And a TerminalSession is created with kind "node_debug"
    And a NodeDebugDescriptor is populated with nodeName "node-worker-01"

  Scenario: Session waits for debug Pod to reach Running phase before opening exec
    Given the operator has confirmed a debug session on Node "node-worker-02"
    And the debug Pod "node-debugger-node-worker-02-1a2b3c4d" has been created
    When the Pod phase transitions from "Pending" to "Running"
    Then the TerminalSession status transitions from "opening" to "open"
    And the WebSocket exec connection is established to the debug Pod
    And the terminal UI displays a shell prompt inside the debug container

  Scenario: Execute node-level diagnostic command inside the debug container
    Given an open node debug session on Node "node-worker-03"
    And the debug container is running image "nicolaka/netshoot:v0.13"
    When the operator runs "nsenter -t 1 -m -u -i -n -p -- ip addr"
    Then the command output is received via stdout channel 1
    And the output lists the node's network interfaces
    And the terminal displays the output correctly decoded from UTF-8

  Scenario: Debug Pod is automatically deleted when session is closed
    Given an open node debug session on Node "node-worker-04"
    And the NodeDebugDescriptor records ephemeralPodName "node-debugger-node-worker-04-deadbeef"
    And expiresAtRFC3339 is 60 seconds after the session started
    When the operator closes the terminal tab
    Then the TerminalSessionActor sends cooperative cancel
    And the exec WebSocket connection closes within 200 milliseconds
    And the KubernetesDebugCreatorPort issues a Pod delete for
      "node-debugger-node-worker-04-deadbeef" in namespace "default"
    And the MutationAuditEntry records the Pod deletion
    And the session status transitions to "closed"
    And the debug Pod is no longer present in the cluster

  Scenario: Debug session fails when target node has NoSchedule taint without toleration
    Given a Node "node-gpu-01" exists with taint "gpu=true:NoSchedule"
    And the debug image spec does not include a toleration for "gpu=true:NoSchedule"
    When the operator requests a debug session on Node "node-gpu-01"
    And the operator confirms the mutating-operation dialog
    Then the KubernetesDebugCreatorPort attempts to create the debug Pod
    And the Kubernetes API returns a scheduling failure (Pod remains "Pending")
    And after the scheduling timeout the session status transitions to "error"
    And the terminal UI displays an error message explaining the taint conflict
    And the partially-created debug Pod is deleted by the cleanup path
    And no exec WebSocket connection is opened
