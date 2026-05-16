// Views/Inspector/ResourceInspectorContent.swift — app_shell bounded context
// DDD role: Protocol — per-kind inspector content factory
// ADR ref: ADR-0073 (inspector trailing column substitutes resource detail tabs)

import SwiftUI

// MARK: - ResourceInspectorContent

/// Factory protocol for per-resource-kind Inspector content.
///
/// Each supported kind provides a type that conforms to this protocol.
/// `ResourceInspectorPanel` iterates the registered `allProviders` list and
/// renders the first non-nil view. New kinds are added by:
///   1. Authoring a new conforming type in `Views/Inspector/<Kind>InspectorView.swift`.
///   2. Appending it to `ResourceInspectorContent.allProviders`.
///
/// This protocol uses `AnyView` erasure deliberately: the Inspector renders
/// exactly one view at a time, so the type-erasure cost is paid once per
/// selection change rather than per frame.
///
/// ADR-0073 §"ResourceInspectorContent protocol".
public protocol ResourceInspectorContentProvider {

    /// Returns a SwiftUI view for `key` if this provider handles the kind,
    /// or `nil` to pass control to the next provider in the chain.
    ///
    /// Implementations should pattern-match on `key.kind` before doing any work.
    static func makeView(for key: InspectorKey) -> AnyView?
}

// MARK: - Provider registry

/// Namespace for the ordered provider registry.
///
/// Wave 3 ships a single `GenericResourceInspectorProvider` stub.
/// Per-kind providers (`PodInspectorProvider`, `DeploymentInspectorProvider`,
/// etc.) are appended in subsequent waves.
public enum ResourceInspectorContent {

    /// Ordered list of registered providers.
    ///
    /// `ResourceInspectorPanel` calls each provider's `makeView(for:)` in
    /// order and renders the first non-nil result. Position 0 has highest
    /// priority.
    ///
    /// `@MainActor` ensures all accesses and `makeView(for:)` calls run on the
    /// main thread, satisfying Swift 6 strict concurrency for the existential
    /// metatype array.
    @MainActor
    public static let allProviders: [any ResourceInspectorContentProvider.Type] = [
        GenericResourceInspectorProvider.self,
    ]

    /// Returns the first non-nil view produced by the registered providers.
    ///
    /// Returns `nil` when no provider handles `key.kind`; the panel renders
    /// an empty state in that case.
    @MainActor
    public static func resolve(for key: InspectorKey) -> AnyView? {
        for provider in allProviders {
            if let view = provider.makeView(for: key) {
                return view
            }
        }
        return nil
    }
}

// MARK: - GenericResourceInspectorProvider

/// Stub provider that handles every kind.
///
/// Returns a simple placeholder text so the Inspector surface is navigable
/// in Wave 3 before per-kind views are authored. Concrete providers
/// (`PodInspectorProvider`, `DeploymentInspectorProvider`, etc.) will be
/// inserted ahead of this provider in `allProviders` in subsequent waves;
/// this stub falls through once they match.
public struct GenericResourceInspectorProvider: ResourceInspectorContentProvider {

    public static func makeView(for key: InspectorKey) -> AnyView? {
        AnyView(
            GenericInspectorPlaceholderView(key: key)
        )
    }
}

// MARK: - GenericInspectorPlaceholderView

/// Placeholder shown by `GenericResourceInspectorProvider` until per-kind views ship.
private struct GenericInspectorPlaceholderView: View {

    let key: InspectorKey

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("\(key.kind)/\(key.name)")
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let ns = key.namespace {
                Text(ns)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Detailed inspector content for this kind will be available in a future release.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
