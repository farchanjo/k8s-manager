// ViewModels/WelcomeTabViewModel.swift — app_shell bounded context
// DDD role: View model — Welcome tab action dispatch
// ADR ref: ADR-0054 (Welcome tab and cluster-acquisition entry surface)

import Foundation
import Observation

// MARK: - WelcomeAction

/// The five canonical start actions surfaced by the Welcome tab.
///
/// Each case carries no associated values — the view model interprets the
/// case and dispatches to the appropriate flow. Implementation contracts for
/// AWS, AKS, and GCP discovery are defined in ADR-0055; clipboard import is
/// defined in ADR-0056.
public enum WelcomeAction: String, Sendable, CaseIterable, Hashable {

    /// Re-runs the first-launch three-step onboarding tour.
    case openOnboardingWizard

    /// Opens the clipboard-paste sheet for kubeconfig import (ADR-0056).
    case addKubeconfigFromClipboard

    /// Opens the macOS native file picker for kubeconfig file import.
    case addKubeconfigFromFile

    /// Triggers the AWS EKS cluster discovery flow (ADR-0055).
    case addClustersFromAWS

    /// Triggers the AKS cluster discovery flow (ADR-0055).
    case addClustersFromAKS

    /// Human-readable tile title.
    public var title: String {
        switch self {
        case .openOnboardingWizard:         return "Open Onboarding Wizard"
        case .addKubeconfigFromClipboard:   return "Add Kubeconfig from Clipboard"
        case .addKubeconfigFromFile:        return "Add Kubeconfig from File"
        case .addClustersFromAWS:           return "Add Clusters from AWS"
        case .addClustersFromAKS:           return "Add Clusters from AKS"
        }
    }

    /// Short description rendered as tile subtitle.
    public var subtitle: String {
        switch self {
        case .openOnboardingWizard:
            return "Restart the getting-started tour."
        case .addKubeconfigFromClipboard:
            return "Paste a YAML kubeconfig directly — no file needed."
        case .addKubeconfigFromFile:
            return "Browse to a kubeconfig file on disk."
        case .addClustersFromAWS:
            return "Discover EKS clusters reachable with your current AWS credentials."
        case .addClustersFromAKS:
            return "Discover AKS clusters reachable with your current Azure credentials."
        }
    }

    /// SF Symbol used for the tile icon.
    public var systemImage: String {
        switch self {
        case .openOnboardingWizard:         return "list.bullet.clipboard"
        case .addKubeconfigFromClipboard:   return "doc.on.clipboard"
        case .addKubeconfigFromFile:        return "folder.badge.plus"
        case .addClustersFromAWS:           return "cloud.fill"
        case .addClustersFromAKS:           return "cloud.fill"
        }
    }
}

// MARK: - WelcomeGuideLink

/// A single entry in the Useful Guides section.
///
/// Targets are read from the application bundle `Info.plist` at view-model
/// init time so that link destinations can be updated without a code change
/// (per ADR-0054).
public struct WelcomeGuideLink: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let url: URL?

    public init(id: String, title: String, url: URL?) {
        self.id = id
        self.title = title
        self.url = url
    }
}

// MARK: - WelcomeTabViewModel

/// Observable view model driving the Welcome tab content area.
///
/// Holds the catalogue of action tiles and Useful Guides links, and dispatches
/// action invocations to a caller-provided handler. The view model is
/// `@MainActor` so SwiftUI can observe its state without bridge hops.
@Observable
@MainActor
public final class WelcomeTabViewModel {

    // MARK: Published state

    /// Ordered catalogue of the five start actions.
    public let actions: [WelcomeAction] = WelcomeAction.allCases

    /// Useful Guides links resolved from the application bundle on init.
    public let guideLinks: [WelcomeGuideLink]

    /// Last action invoked. Cleared after the handler runs. Useful for tests.
    public private(set) var lastInvocation: WelcomeAction?

    // MARK: Dependencies

    /// Caller-injected handler dispatched on every tile tap. The handler runs
    /// on the main actor and is responsible for translating the action into a
    /// concrete workflow (sheet presentation, sheet dismissal, etc.).
    private let handler: (@MainActor (WelcomeAction) -> Void)?

    // MARK: Init

    /// Designated initialiser.
    ///
    /// - Parameters:
    ///   - bundle: Source of guide link URLs. Defaults to `Bundle.main` for
    ///     production callers; tests should pass a stub bundle.
    ///   - handler: Closure invoked on every action tap. Defaults to a no-op
    ///     so that the view can render in previews without wiring.
    public init(
        bundle: Bundle = .main,
        handler: (@MainActor (WelcomeAction) -> Void)? = nil
    ) {
        self.handler = handler
        self.guideLinks = WelcomeTabViewModel.resolveGuideLinks(bundle: bundle)
    }

    // MARK: Actions

    /// Invokes the handler for `action` and records the invocation.
    public func invoke(_ action: WelcomeAction) {
        lastInvocation = action
        handler?(action)
    }

    // MARK: Private helpers

    /// Resolves Useful Guides URLs from the bundle Info.plist.
    ///
    /// Three Info.plist keys are honoured:
    /// - `WelcomeGuideLinkGettingStarted` → "Getting Started"
    /// - `WelcomeGuideLinkAssistant` → "Using the AI Assistant"
    /// - `WelcomeGuideLinkSupport` → "Getting Support"
    ///
    /// Missing keys produce a `WelcomeGuideLink` with `url == nil`; the view
    /// renders such entries as disabled `Link` controls.
    private static func resolveGuideLinks(bundle: Bundle) -> [WelcomeGuideLink] {
        let entries: [(String, String)] = [
            ("WelcomeGuideLinkGettingStarted", "Getting Started"),
            ("WelcomeGuideLinkAssistant",      "Using the AI Assistant"),
            ("WelcomeGuideLinkSupport",        "Getting Support"),
        ]
        return entries.map { key, title in
            let raw = bundle.object(forInfoDictionaryKey: key) as? String
            let url = raw.flatMap { URL(string: $0) }
            return WelcomeGuideLink(id: key, title: title, url: url)
        }
    }
}
