// Tests/AppShellTests/WelcomeTabViewModelTests.swift
// Target: AppShellTests
// Coverage: ADR-0054 Welcome action catalogue + guide link resolution

import XCTest
@testable import AppShell

@MainActor
final class WelcomeTabViewModelTests: XCTestCase {

    // MARK: - Catalogue completeness (five canonical actions)

    func test_actions_returnsAllFiveCanonicalActions() {
        let sut = WelcomeTabViewModel()

        XCTAssertEqual(sut.actions.count, 5)
        XCTAssertEqual(sut.actions, [
            .openOnboardingWizard,
            .addKubeconfigFromClipboard,
            .addKubeconfigFromFile,
            .addClustersFromAWS,
            .addClustersFromAKS,
        ])
    }

    // MARK: - Tile copy invariants

    func test_actionTitles_matchSpec() {
        XCTAssertEqual(WelcomeAction.openOnboardingWizard.title, "Open Onboarding Wizard")
        XCTAssertEqual(WelcomeAction.addKubeconfigFromClipboard.title, "Add Kubeconfig from Clipboard")
        XCTAssertEqual(WelcomeAction.addKubeconfigFromFile.title, "Add Kubeconfig from File")
        XCTAssertEqual(WelcomeAction.addClustersFromAWS.title, "Add Clusters from AWS")
        XCTAssertEqual(WelcomeAction.addClustersFromAKS.title, "Add Clusters from AKS")
    }

    func test_actionIcons_useSpecifiedSFSymbols() {
        XCTAssertEqual(WelcomeAction.openOnboardingWizard.systemImage, "list.bullet.clipboard")
        XCTAssertEqual(WelcomeAction.addKubeconfigFromClipboard.systemImage, "doc.on.clipboard")
        XCTAssertEqual(WelcomeAction.addKubeconfigFromFile.systemImage, "folder.badge.plus")
        XCTAssertEqual(WelcomeAction.addClustersFromAWS.systemImage, "cloud.fill")
        XCTAssertEqual(WelcomeAction.addClustersFromAKS.systemImage, "cloud.fill")
    }

    // MARK: - Handler dispatch

    func test_invoke_callsHandlerWithProvidedAction() {
        var captured: WelcomeAction?
        let sut = WelcomeTabViewModel { action in
            captured = action
        }

        sut.invoke(.addKubeconfigFromClipboard)

        XCTAssertEqual(captured, .addKubeconfigFromClipboard)
        XCTAssertEqual(sut.lastInvocation, .addKubeconfigFromClipboard)
    }

    func test_invoke_recordsLastInvocationEvenWithoutHandler() {
        let sut = WelcomeTabViewModel()

        sut.invoke(.addClustersFromAWS)

        XCTAssertEqual(sut.lastInvocation, .addClustersFromAWS)
    }

    // MARK: - Useful Guides resolution

    func test_guideLinks_returnsAllThreeEntries() {
        let sut = WelcomeTabViewModel(bundle: .main)

        XCTAssertEqual(sut.guideLinks.count, 3)
        XCTAssertEqual(sut.guideLinks.map(\.id), [
            "WelcomeGuideLinkGettingStarted",
            "WelcomeGuideLinkAssistant",
            "WelcomeGuideLinkSupport",
        ])
    }

    func test_guideLinks_titlesMatchSpec() {
        let sut = WelcomeTabViewModel(bundle: .main)

        XCTAssertEqual(sut.guideLinks[0].title, "Getting Started")
        XCTAssertEqual(sut.guideLinks[1].title, "Using the AI Assistant")
        XCTAssertEqual(sut.guideLinks[2].title, "Getting Support")
    }

    func test_guideLinks_missingInfoPlistKey_producesNilURL() {
        // `Bundle.main` for the test runner does not declare the welcome guide
        // Info.plist keys, so every link resolves to a nil URL — the view
        // renders these as disabled entries.
        let sut = WelcomeTabViewModel(bundle: .main)

        for link in sut.guideLinks {
            XCTAssertNil(link.url, "\(link.id) must be nil when key is absent from bundle")
        }
    }
}
