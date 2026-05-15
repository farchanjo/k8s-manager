# DDD role: BehaviouralSpecification
# Bounded context: port_forwarding
# References: ADR-0014

Feature: Multi-port forwarding — frame multiplexing per portIndex
  As an operator
  I want to forward multiple ports in a single session with correct frame multiplexing
  So that I can access multiple services in a Pod over a single WebSocket connection

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Pod "app-0" in namespace "default" exposes ports 8080 (HTTP) and 9090 (metrics)

  @happy @lifecycle
  Scenario: Three ports forwarded with correct port-index byte in each frame
    When the operator opens a port-forward session for ports 8080, 9090, and 3000 on "app-0"
    Then the HTTP upgrade URL includes "ports=8080&ports=9090&ports=3000" query parameters
    And the WebSocket upgrade succeeds with subprotocol "portforward.k8s.io"
    And three separate TCP server sockets are bound on loopback, one per port mapping
    And the session aggregate records portIndex 0 for port 8080, index 1 for 9090, index 2 for 3000
    When a TCP client writes bytes to the local port mapped to 8080
    Then the binary WebSocket frame has channel byte 0x00 (data) and portIndex byte 0x01
    When a TCP client writes bytes to the local port mapped to 9090
    Then the binary WebSocket frame has channel byte 0x00 (data) and portIndex byte 0x01

  @happy @lifecycle
  Scenario: Independent byte counters per portIndex
    Given the three-port session is in "running" state
    When 512 bytes are written to the port-8080 socket and 1024 bytes to the port-9090 socket
    Then the #BytesTransferred event for portIndex 0 shows sentBytes 512
    And the #BytesTransferred event for portIndex 1 shows sentBytes 1024
    And the counters for each portIndex are independent (no cross-contamination)

  @failure @lifecycle
  Scenario: Error channel frame for one portIndex does not close other ports
    Given the three-port session is in "running" state
    When the API server sends an error frame (channel byte 0x01) for portIndex 1 (port 9090)
    Then the TCP socket for portIndex 1 is closed
    And the #PortError event is emitted for portIndex 1
    And the TCP sockets for portIndex 0 (port 8080) and portIndex 2 (port 3000) remain open
    And the session remains in "running" state

  @failure @lifecycle
  Scenario: EOF frame on data channel for one port closes that connection only
    Given a local TCP client is connected to the port mapped to 9090
    When the API server sends a zero-length data frame for portIndex 1
    Then that specific TCP client connection is closed (half-close signalled)
    And the server socket for port 9090 remains open (able to accept new connections)
    And other existing connections on other portIndexes are unaffected
