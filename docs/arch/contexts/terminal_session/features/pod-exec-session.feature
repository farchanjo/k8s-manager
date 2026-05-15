# DDD role: BehaviouralSpecification
Feature: Pod exec session
  As a cluster operator using K8sManager
  I want to open an interactive terminal session inside a running Pod container
  So that I can inspect application state, run commands, and debug issues
  without leaving the application

  Background:
    Given a kubeconfig context "prod-cluster" is active
    And the cluster is reachable and responds to API requests
    And the WebSocket endpoint negotiates subprotocol "v5.channel.k8s.io"

  Scenario: Open exec session in a single-container Pod
    Given a Pod "nginx-7d8f9c-xkz5p" exists in namespace "default"
    And the Pod has exactly one container named "nginx"
    And the Pod phase is "Running"
    When the operator opens a terminal for Pod "nginx-7d8f9c-xkz5p" in namespace "default"
    Then a TerminalSession is created with kind "pod_exec"
    And targetRef.podName is "nginx-7d8f9c-xkz5p"
    And targetRef.containerName is "nginx"
    And the session status transitions to "opening" then "open"
    And a WebSocket connection is established to the exec subresource
    And the terminal UI displays a prompt from the container

  Scenario: Select a specific container in a multi-container Pod
    Given a Pod "sidecar-pod-abc12" exists in namespace "payments"
    And the Pod has containers named "app", "envoy", and "filebeat"
    And the Pod phase is "Running"
    When the operator opens a terminal for Pod "sidecar-pod-abc12" in namespace "payments"
    Then the UI presents a container selection dialog listing "app", "envoy", "filebeat"
    When the operator selects container "envoy"
    Then a TerminalSession is created with targetRef.containerName "envoy"
    And the exec WebSocket path encodes containerName "envoy" as a query parameter
    And the terminal UI displays a prompt from the "envoy" container

  Scenario: Resize terminal when UI geometry changes
    Given an open terminal session for Pod "api-server-xyz" container "api"
    And the current terminal size is 80 columns by 24 rows
    When the operator resizes the terminal window to 120 columns by 40 rows
    Then a resize debounce interval of 100ms is observed
    And a ResizeFrame is sent on channel 4 with Width 120 and Height 40
    And the JSON payload of the resize frame is "{\"Width\":120,\"Height\":40}"
    And no intermediate resize frames are sent during the debounce window

  Scenario: Input containing a multi-byte UTF-8 character is forwarded on channel 0
    Given an open terminal session for Pod "worker-pod-001" container "worker"
    When the operator types the character "€" (U+20AC, 3-byte UTF-8 sequence 0xE2 0x82 0xAC)
    Then a StdinFrame is constructed with channel 0
    And the bytes field encodes the 3-byte UTF-8 sequence for "€"
    And the wire frame begins with byte 0x00 followed by 0xE2 0x82 0xAC
    And the character is echoed back in the terminal output via stdout channel 1

  Scenario: Ctrl-C sends interrupt byte 0x03 on channel 0
    Given an open terminal session for Pod "job-runner-42" container "runner"
    And a long-running command is executing in the terminal
    When the operator presses Ctrl-C
    Then a StdinFrame is constructed with channel 0
    And the bytes field contains a single byte with value 0x03
    And the wire frame begins with byte 0x00 followed by byte 0x03
    And the remote process receives SIGINT and terminates

  Scenario: Operator cancels session and WebSocket closes within 200ms
    Given an open terminal session for Pod "debug-pod-99" container "shell"
    When the operator closes the terminal tab
    Then cooperative task cancellation is dispatched to the TerminalSessionActor
    And the URLSessionWebSocketTask receives a cancel signal
    And the WebSocket connection is closed within 200 milliseconds
    And the session status transitions to "closing" then "closed"
    And the TerminalSession is removed from the OpenTerminalsReadModel

  Scenario: Exit code 0 is captured when the remote process exits cleanly
    Given an open terminal session for Pod "batch-job-pod" container "job"
    And the operator runs "exit 0" in the terminal
    When the remote process exits with code 0
    Then an ErrorFrame is received on channel 3
    And the JSON payload is "{\"ExitCode\":0}"
    And the session status transitions to "closed"
    And the TerminalSession.exitCode is 0
    And the terminal UI displays "Process exited (0)"

  Scenario: Exit code 127 is captured when the remote process exits with an error
    Given an open terminal session for Pod "batch-job-pod" container "job"
    And the operator runs "exit 127" in the terminal
    When the remote process exits with code 127
    Then an ErrorFrame is received on channel 3
    And the JSON payload is "{\"ExitCode\":127}"
    And the session status transitions to "closed"
    And the TerminalSession.exitCode is 127
    And the terminal UI displays "Process exited (127)" with a warning indicator
