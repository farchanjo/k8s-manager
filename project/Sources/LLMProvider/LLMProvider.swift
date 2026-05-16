// LLMProvider.swift — llm_provider domain core
// Bounded context: llm_provider (per ADR-0005)
//
// Domain types live in `Domain/`, hexagonal port protocols in `Ports/`.
// This file intentionally exports no namespace enum: a top-level type named
// `LLMProvider` would shadow the module name and break adapter-side type
// qualification such as `LLMProvider.ProviderProfile` when both this module
// and another module export the same simple type name.
