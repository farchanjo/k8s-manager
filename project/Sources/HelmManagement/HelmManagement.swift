// HelmManagement.swift — helm_management domain core
// Bounded context: helm_management (per ADR-0005)
// ADR ref: ADR-0015 (Helm native phased), ADR-0046 (rollback lease mutex)
//
// Domain types live in `Domain/`, hexagonal port protocols in `Ports/`.
// No namespace enum is declared: a top-level type named `HelmManagement`
// would shadow the module name and break adapter-side type qualification
// (e.g. `HelmManagement.Release`) when both this module and another module
// export the same simple type name — same rationale as ClusterConnectivity.
