# DDD role: BehaviouralSpecification
# Bounded context: cluster_intelligence
# References: ADR-0009, ADR-0019

Feature: In-process MCP transport uses InMemoryTransport with no network socket
  As a security reviewer
  I want the in-process MCP server to communicate via AsyncStream pairs rather than sockets
  So that there is no local network attack surface for the MCP protocol

  Background:
    Given the application has started
    And the MCP server is initialised with InMemoryTransport (modelcontextprotocol/swift-sdk v0.12.1)

  @security @happy
  Scenario: InMemoryTransport does not open any local socket or pipe
    When the MCP server is initialised
    Then an lsof inspection of the application process shows no LISTEN sockets owned by the MCP server
    And no Unix domain socket, TCP socket, or named pipe is created for the MCP transport
    And the MCP communication happens entirely through Swift AsyncStream pairs in-process

  @security @happy
  Scenario: MCP protocol message boundaries are enforced by the AsyncStream pair
    Given the MCP host and server are connected via InMemoryTransport
    When the host sends a tools/call request
    Then the request is delivered to the server through the input AsyncStream
    And the server's response is delivered back through the output AsyncStream
    And no serialisation to bytes over a socket occurs at any point in the MCP protocol exchange

  @failure @lifecycle
  Scenario: External process cannot access MCP tools because there is no socket to connect to
    When an external process attempts to connect to any local port associated with "K8sManager" MCP
    Then no such port exists (lsof confirms no LISTEN socket for the application on MCP-related ports)
    And the external process cannot invoke any MCP tool
    And the read-only Kubernetes tools are inaccessible from outside the application process

  @happy @lifecycle
  Scenario: InMemoryTransport is torn down cleanly when the assistant session closes
    Given an assistant chat session is open and the MCP server is connected via InMemoryTransport
    When the operator closes the assistant chat session
    Then the AsyncStream pair for the InMemoryTransport is cancelled
    And the MCP server receives a session-end signal
    And no dangling async tasks remain after the session closes
    And a new InMemoryTransport pair is created when the next assistant session opens
