// ClusterConnectivity.swift — cluster_connectivity domain core
// Bounded context: cluster_connectivity (per ADR-0005)
//
// Domain types live in `Domain/`, hexagonal port protocols in `Ports/`,
// and the per-cluster actor in `Actors/`. This file intentionally exports
// no namespace enum: a top-level type named `ClusterConnectivity` would
// shadow the module name and break adapter-side type qualification such
// as `ClusterConnectivity.AuthInfo` when both this module and another
// module export the same simple type name.
