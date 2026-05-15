# DDD role: ChaosScenario
# Bounded context: cluster_intelligence
# Failure mode: InMemoryTransport socket leak (isolation regression)
# References: ADR-0041, ADR-0031, ADR-0034

Feature: InMemoryTransport never opens a network socket during MCP tool dispatch
  As a platform engineer
  I need the in-process MCP server to use only in-memory channels
  So that no unintended network surface is exposed by the AI subsystem

  Background:
    Given the assistant_chat bounded context is initialized
    And the MCP server is configured to use InMemoryTransport (not TCP/stdio)
    And lsof / proc monitoring is active for the app process

  @chaos @network
  Scenario: MCP server initialization does not open any listening socket
    When the app launches and the in-process MCP server starts
    Then lsof reports no LISTEN sockets for the app process on any port
    And the MCP server is reachable only via the in-memory channel
    And the metric "mcp_socket_open_count" is 0

  @chaos @network
  Scenario: Multiple concurrent tool invocations do not open ephemeral sockets
    Given the assistant invokes 5 MCP tools concurrently (kube_logs, get_pod, list_pods, apply_manifest, list_events)
    When all 5 tool calls are dispatched via InMemoryTransport
    Then lsof still reports no new LISTEN or ESTABLISHED sockets for the app process
    And all 5 tool calls complete successfully via the in-memory channel
    And the metric "mcp_socket_open_count" remains 0

  @chaos @network
  Scenario: InMemoryTransport teardown on app close leaves no lingering sockets or file descriptors
    Given the MCP server has processed 20 tool calls during the session
    When the app closes and the MCP server shuts down
    Then lsof confirms no MCP-related FDs remain after shutdown
    And no zombie threads are detectable for the MCP server goroutines
