// TerminalSession.swift — terminal_session domain core
// Bounded context: terminal_session (per ADR-0005 / ADR-0017)
//
// Domain types live in `Domain/`, hexagonal port protocols in `Ports/`.
// This file intentionally exports no namespace enum: a top-level type named
// `TerminalSession` would shadow the module name and break adapter-side type
// qualification when both this module and another export the same simple type
// name (mirrors the pattern established by ClusterConnectivity.swift).
