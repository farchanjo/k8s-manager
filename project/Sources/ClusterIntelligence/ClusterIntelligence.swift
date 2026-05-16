// ClusterIntelligence.swift — cluster_intelligence domain core
// Bounded context: cluster_intelligence (per ADR-0009)
//
// Domain types live in `Domain/`, hexagonal port protocols in `Ports/`.
// This file intentionally exports no namespace enum: a top-level type named
// `ClusterIntelligence` would shadow the module name and break adapter-side
// type qualification such as `ClusterIntelligence.MCPInvocation` when both
// this module and another module export the same simple type name.
