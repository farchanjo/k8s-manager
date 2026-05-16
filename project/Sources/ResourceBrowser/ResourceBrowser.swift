// ResourceBrowser.swift — resource_browser bounded context
// Bounded context: resource_browser (per ADR-0005)
// ADR refs: ADR-0012 (mutating operations policy), ADR-0013 (kind catalogue)
//
// Domain types live in `Domain/`, hexagonal port protocols in `Ports/`.
// This file intentionally exports no namespace enum: a top-level type named
// `ResourceBrowser` would shadow the module name and break adapter-side type
// qualification. The comment header mirrors the ClusterConnectivity pattern.
