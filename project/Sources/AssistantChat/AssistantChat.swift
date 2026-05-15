// AssistantChat.swift — domain core placeholder
// Bounded context: assistant_chat (per ADR-0005)
// Status: skeleton; domain types pending CUE schema extraction.
import Foundation

/// Namespace marker for the AssistantChat bounded context.
///
/// Domain types, ports, and actors land under this enum in subsequent rounds.
/// This file exists so the target compiles cleanly under Swift 6 strict concurrency.
public enum AssistantChat: Sendable {
    /// Build identifier — bumped manually until CI emits this.
    public static let moduleVersion = "0.0.1-skeleton"
}
