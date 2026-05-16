// AnalyticsDashboard.swift — analytics_dashboard bounded context
// Bounded context: analytics_dashboard (per ADR-0024)
//
// Domain types live in `Domain/`, hexagonal port protocols in `Ports/`,
// domain services and aggregates in `Actors/`.
// This file intentionally exports no namespace enum: a top-level type named
// `AnalyticsDashboard` would shadow the module name and break adapter-side
// type qualification such as `AnalyticsDashboard.Dashboard` when both this
// module and another module export the same simple type name.
