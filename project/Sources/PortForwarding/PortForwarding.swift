// PortForwarding.swift — port_forwarding domain core
// Bounded context: port_forwarding (per ADR-0005 / ADR-0014)
//
// Domain types live in `Domain/`, hexagonal port protocols in `Ports/`.
// This file intentionally exports no namespace enum: a top-level type named
// `PortForwarding` would shadow the module name and break adapter-side
// type qualification such as `PortForwarding.PortForwardSession` when both
// this module and another module export the same simple type name.
