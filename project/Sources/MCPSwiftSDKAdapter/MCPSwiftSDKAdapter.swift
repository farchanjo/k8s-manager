// MCPSwiftSDKAdapter.swift — infrastructure adapter target
// Implements: MCPTransportPort (MCPInProcessTransport), mutating handlers (MCPMutatingToolHandlers)
// Library: modelcontextprotocol/swift-sdk 0.12.1 (Tier A per ADR-0019)
// ADR ref: ADR-0009 (MCP host + in-process server)

import Foundation

// MARK: - Module version

/// Semantic version of the MCPSwiftSDKAdapter target.
///
/// Bumped on every breaking change to the adapter's public surface.
public let mcpSwiftSDKAdapterVersion = "0.1.0"
