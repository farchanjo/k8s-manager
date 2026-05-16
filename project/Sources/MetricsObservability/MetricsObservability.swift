// MetricsObservability.swift — metrics_observability bounded context
// Bounded context: metrics_observability (per ADR-0005)
//
// Domain types live in `Domain/`, hexagonal port protocols in `Ports/`.
// This file intentionally exports no namespace enum: a top-level type named
// `MetricsObservability` would shadow the module name and break adapter-side
// type qualification such as `MetricsObservability.PromQuery` when both this
// module and another module export the same simple type name.
