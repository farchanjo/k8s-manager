// Tests/AppShellTests/DockedYAMLEditorPaneActorTests.swift
// Target: AppShellTests
// Coverage: ADR-0064 docked YAML editor pane actor invariants
//
// Verifies:
// 1. openDraft inserts a draft and makes the pane open.
// 2. openDraft for the same resource is a no-op (pane stays, draft unchanged).
// 3. openDraft for a different resource replaces the draft when isDirty == false.
// 4. closeDraft clears the active draft and marks the pane closed.
// 5. updateDraftText mutates draftText and isDirty correctly.
// 6. toggleDiffOverlay flips isDiffOverlayVisible.
// 7. setPaneHeight clamps to 200 pt minimum.
// 8. loadFromDisk restores persisted draft with isDirty preserved.
// 9. loadFromDisk on a missing file keeps default empty state.

import XCTest
@testable import AppShell
import SharedKernel

final class DockedYAMLEditorPaneActorTests: XCTestCase {

    // MARK: Helpers

    private var tmpFile: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)/docked-yaml-editor-pane.json")
    }

    private func makeActor(persistenceURL: URL? = nil) -> DockedYAMLEditorPaneActor {
        DockedYAMLEditorPaneActor(persistenceURL: persistenceURL ?? tmpFile)
    }

    private func makeResourceRef(kind: String = "Deployment", name: String = "web-api") -> ResourceRef {
        ResourceRef(
            kind: ResourceKind(group: "apps", version: "v1", kind: kind),
            namespace: "production",
            name: name
        )
    }

    private func makeDraft(
        clusterId: ClusterId = ClusterId(UUID().uuidString),
        ref: ResourceRef? = nil,
        text: String = "apiVersion: apps/v1\nkind: Deployment",
        isDirty: Bool = false
    ) -> DockedEditorDraft {
        DockedEditorDraft(
            clusterId: clusterId,
            ref: ref ?? makeResourceRef(),
            draftText: text,
            isDirty: isDirty
        )
    }

    // MARK: - openDraft

    func test_openDraft_makesPaneOpen() async {
        let sut = makeActor()
        let draft = makeDraft()

        await sut.openDraft(draft)

        let isOpen = await sut.state.isOpen
        XCTAssertTrue(isOpen)
    }

    func test_openDraft_setsActiveDraft() async {
        let sut = makeActor()
        let draft = makeDraft()

        await sut.openDraft(draft)

        let activeDraftId = await sut.state.activeDraftId
        XCTAssertEqual(activeDraftId, draft.id)
    }

    func test_openDraft_sameResource_isNoOp() async {
        let sut = makeActor()
        let ref = makeResourceRef()
        let clusterId = ClusterId(UUID().uuidString)
        let original = makeDraft(clusterId: clusterId, ref: ref, text: "original")

        await sut.openDraft(original)

        // Re-open same resource — should not replace the draft
        let duplicate = makeDraft(clusterId: clusterId, ref: ref, text: "different")
        await sut.openDraft(duplicate)

        let draftText = await sut.state.activeDraft?.draftText
        XCTAssertEqual(draftText, "original", "Same-resource open must not replace the draft")
    }

    func test_openDraft_differentResource_replacesWhenNotDirty() async {
        let sut = makeActor()
        let clusterId = ClusterId(UUID().uuidString)
        let first = makeDraft(clusterId: clusterId, ref: makeResourceRef(name: "service-a"))
        let second = makeDraft(clusterId: clusterId, ref: makeResourceRef(name: "service-b"))

        await sut.openDraft(first)
        await sut.openDraft(second)

        let activeDraftId = await sut.state.activeDraftId
        XCTAssertEqual(activeDraftId, second.id, "Non-dirty draft must be replaced on different resource open")
    }

    func test_openDraft_withTerminalBanner_storesBannerFlag() async {
        let sut = makeActor()
        let draft = makeDraft()

        await sut.openDraft(draft, showTerminalBanner: true)

        let bannerVisible = await sut.state.showTerminalRunningBanner
        XCTAssertTrue(bannerVisible)
    }

    // MARK: - closeDraft

    func test_closeDraft_clearsDraftAndClosePane() async {
        let sut = makeActor()
        await sut.openDraft(makeDraft())

        await sut.closeDraft()

        let isOpen = await sut.state.isOpen
        let draft = await sut.state.activeDraft
        XCTAssertFalse(isOpen)
        XCTAssertNil(draft)
    }

    func test_closeDraft_clearsTerminalBanner() async {
        let sut = makeActor()
        await sut.openDraft(makeDraft(), showTerminalBanner: true)

        await sut.closeDraft()

        let bannerVisible = await sut.state.showTerminalRunningBanner
        XCTAssertFalse(bannerVisible)
    }

    // MARK: - updateDraftText

    func test_updateDraftText_mutatesTodraftTextAndIsDirty() async {
        let sut = makeActor()
        await sut.openDraft(makeDraft(text: "original"))

        await sut.updateDraftText("edited", isDirty: true)

        let draftText = await sut.state.activeDraft?.draftText
        let isDirty = await sut.state.activeDraft?.isDirty
        XCTAssertEqual(draftText, "edited")
        XCTAssertTrue(isDirty == true)
    }

    func test_updateDraftText_noDraft_isNoOp() async {
        let sut = makeActor()

        await sut.updateDraftText("edited", isDirty: true)

        let draft = await sut.state.activeDraft
        XCTAssertNil(draft)
    }

    // MARK: - toggleDiffOverlay

    func test_toggleDiffOverlay_flipsFlag() async {
        let sut = makeActor()
        await sut.openDraft(makeDraft())

        await sut.toggleDiffOverlay()
        let afterFirst = await sut.state.activeDraft?.isDiffOverlayVisible

        await sut.toggleDiffOverlay()
        let afterSecond = await sut.state.activeDraft?.isDiffOverlayVisible

        XCTAssertTrue(afterFirst == true)
        XCTAssertFalse(afterSecond == true)
    }

    // MARK: - setPaneHeight

    func test_setPaneHeight_clampedToMinimum() async {
        let sut = makeActor()

        await sut.setPaneHeight(80)

        let height = await sut.state.paneHeight
        XCTAssertEqual(height, 200, accuracy: 0.01)
    }

    func test_setPaneHeight_validValueAccepted() async {
        let sut = makeActor()

        await sut.setPaneHeight(450)

        let height = await sut.state.paneHeight
        XCTAssertEqual(height, 450, accuracy: 0.01)
    }

    // MARK: - Persistence round-trip

    func test_persistence_roundTrip_restoresDraftWithIsDirtyPreserved() async throws {
        let url = tmpFile
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // Write state via the actor
        let writer = DockedYAMLEditorPaneActor(persistenceURL: url)
        let draft = makeDraft(text: "apiVersion: v1", isDirty: true)
        await writer.openDraft(draft)
        await writer.updateDraftText("modified text", isDirty: true)
        await writer.setPaneHeight(350)
        // Allow debounce to settle
        try await Task.sleep(for: .milliseconds(700))

        // Read via a fresh actor
        let reader = DockedYAMLEditorPaneActor(persistenceURL: url)
        try await reader.loadFromDisk()

        let restoredDraft = await reader.state.activeDraft
        XCTAssertNotNil(restoredDraft)
        XCTAssertEqual(restoredDraft?.draftText, "modified text")
        XCTAssertTrue(restoredDraft?.isDirty == true,
                      "isDirty must be preserved across persistence so unsaved edits are recoverable")
        let restoredHeight = await reader.state.paneHeight
        XCTAssertEqual(restoredHeight, 350, accuracy: 0.01)
    }

    func test_loadFromDisk_missingFile_keepsDefaultState() async throws {
        let sut = makeActor(persistenceURL: tmpFile)

        try await sut.loadFromDisk()

        let isOpen = await sut.state.isOpen
        XCTAssertFalse(isOpen)
    }
}
