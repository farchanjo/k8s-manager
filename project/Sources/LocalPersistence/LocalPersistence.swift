// LocalPersistence.swift — local_persistence domain core
// Bounded context: local_persistence (per ADR-0005, ADR-0010, ADR-0047)
//
// Domain types live in `Domain/`, hexagonal port protocols in `Ports/`.
// This file intentionally exports no namespace enum: a top-level type named
// `LocalPersistence` would shadow the module name and break adapter-side
// qualified references such as `LocalPersistence.KeychainEntry` when both this
// module and another module export the same simple type name.
//
// Import policy (domain core only):
//   Foundation, SharedKernel, Dependencies, Logging
//   NO: GRDB, Security — those belong exclusively to adapter targets.
