# DDD role: BehaviouralSpecification
Feature: Port-forward session lifecycle and failure handling
  As a cluster operator using K8sManager
  I want port-forward sessions to close cleanly when I stop them
  and to surface clear failures when the tunnel breaks
  So that I am never left with dangling sockets or silent data loss

  Background:
    Given a kubeconfig context "prod-cluster" is active
    And the cluster is reachable and responds to API requests
    And the Kubernetes API server is version 1.31 or later

  Scenario: Manually stopping a running session closes the listener and WebSocket
    Given a port-forward session is running for Pod "nginx-7d8f9c-xkz5p" in namespace "default"
    And the session has status "running"
    And port 8080 is forwarded to localPort 8080
    And a local TCP client is connected to 127.0.0.1:8080
    When the operator stops the session via the K8sManager UI
    Then the session status transitions to "closing"
    And PortForwardManagerActor sends a WebSocket Close frame with code 1000 (normal closure)
    And all active per-connection Tasks are cancelled
    And the local TCP listener on 127.0.0.1:8080 is closed within 200 ms
    And the existing TCP client connection receives EOF
    And a ListenerClosed event is emitted for portIndex 0
    And a SessionClosed event is emitted
    And the session status transitions to "closed"

  Scenario: Application quit closes all running sessions before process exit
    Given three port-forward sessions are running:
      | sessionId (placeholder) | localPort | Pod               |
      | session-A               | 5432      | postgres-0        |
      | session-B               | 6379      | redis-primary-0   |
      | session-C               | 9090      | prometheus-0      |
    When the operator quits K8sManager (applicationWillTerminate fires)
    Then all three sessions receive a stop() call from the AppDelegate shutdown handler
    And each session transitions through "closing" to "closed"
    And all three local TCP listeners are closed
    And all three WebSocket connections send a Close frame
    And the shutdown completes within the 500 ms total deadline
    And no POSIX sockets are left in LISTEN or ESTABLISHED state after process exit

  Scenario: Pod termination during an active session causes SessionFailed
    Given a port-forward session is running for Pod "worker-abc12" in namespace "jobs"
    And the session has status "running"
    And port 8000 is forwarded to localPort 8000
    When the Pod "worker-abc12" is deleted by an external operator or a Deployment rollout
    And the Kubernetes API server closes the WebSocket connection abnormally
    Then PortForwardManagerActor receives a WebSocket close event with a non-normal code
    And a SessionFailed event is emitted with errorCode "websocket_closed_abnormally"
    And the detail field contains a human-readable message (e.g. "Pod was deleted")
    And the detail field does not contain any credential material
    And the local TCP listener on port 8000 is closed
    And any connected TCP clients receive EOF
    And the session status transitions to "error"
    And the UI surfaces the SessionFailed event to the operator with a retry prompt

  Scenario: WebSocket upgrade rejected with 403 Forbidden causes SessionFailed
    Given a kubeconfig context "restricted-cluster" is active
    And the operator's service account does not have RBAC permission for pods/portforward
    And a Pod "api-server-001" exists in namespace "backend"
    When the operator attempts to open a port-forward session for Pod "api-server-001"
    Then PortForwardManagerActor sends the WebSocket upgrade request
    And the Kubernetes API server responds with HTTP 403 Forbidden
    And the WebSocket handshake fails before any TCP listener is bound
    And a SessionFailed event is emitted with errorCode "websocket_upgrade_rejected"
    And the detail field includes the HTTP status code "403" without credential material
    And no ListenerBound event is emitted
    And the session status is set to "error"
    And the UI displays an error message indicating insufficient RBAC permissions

  Scenario: Operator manually re-opens a session after a failure
    Given a port-forward session for Pod "db-primary-0" reached status "error"
    And the session has errorCode "websocket_closed_abnormally"
    And the Pod "db-primary-0" is currently in "Running" phase again
    When the operator clicks "Retry" or "Open new session" in the K8sManager UI
    Then a new PortForwardSession aggregate is created with a fresh UUIDv7 id
    And the new session begins with status "opening"
    And the previous session remains in status "error" (no in-place mutation)
    And the new session transitions to "running" upon successful WebSocket upgrade
    And the new session's ListenerBound event shows the newly assigned localPort
    And the ActivePortForwardsReadModel reflects only the new "running" session
    And the failed session is moved to a closed sessions history view in the UI
