// AppShell.swift — domain core placeholder
// Bounded context: app_shell (per ADR-0005)
// Status: skeleton; domain types pending CUE schema extraction.
import Foundation
import SwiftUI

/// Namespace marker for the AppShell bounded context.
///
/// Domain types, ports, and actors land under this enum in subsequent rounds.
/// This file exists so the target compiles cleanly under Swift 6 strict concurrency.
public enum AppShell: Sendable {
    /// Build identifier — bumped manually until CI emits this.
    public static let moduleVersion = "0.0.1-skeleton"
}

/// Root SwiftUI scene placeholder. Wired by K8sManagerApp composition root.
public struct K8sManagerRootScene: Scene {
    public init() {}
    public var body: some Scene {
        WindowGroup {
            ContentPlaceholderView()
        }
    }
}

struct ContentPlaceholderView: View {
    var body: some View {
        VStack {
            Text("K8sManager — skeleton")
                .font(.title)
            Text("Spec lock 2026-05-15 baseline")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
    }
}
