// AssistantChat.swift — assistant_chat domain core
// Bounded context: assistant_chat (per ADR-0005)
//
// Domain types live in `Domain/`, hexagonal port protocols in `Ports/`.
// This file intentionally exports no namespace enum: a top-level type named
// `AssistantChat` would shadow the module name and break adapter-side type
// qualification such as `AssistantChat.ChatSession` when both this module and
// another module export the same simple type name.
