// DraftAutoSaverTests.swift — ResourceBrowserTests target
// Coverage: DraftAutoSaver — debounce flush, dirty tracking, Secret redaction.
// ADR refs: ADR-0030 (draft auto-save, 5-second debounce, Secret redaction invariant)

import XCTest
import Dependencies
@testable import ResourceBrowser
import SharedKernel

// MARK: - Fake

private actor FakeDraftStoragePort: DraftStoragePort {
    var savedDrafts: [Draft] = []

    func save(_ draft: Draft) async throws {
        savedDrafts.append(draft)
    }
    func latestDraft(forSession sessionId: UUID) async throws -> Draft? { nil }
    func drafts(forResource resourceRef: ResourceRef) async throws -> [Draft] { [] }
    func delete(id: UUID) async throws {}
    func pruneStale(olderThan: String) async throws -> Int { 0 }
}

// MARK: - Tests

final class DraftAutoSaverFlushTests: XCTestCase {

    func test_flush_persistsDraftImmediately() async throws {
        let storage = FakeDraftStoragePort()
        let sessionId = UUID()

        let saver = withDependencies {
            $0.draftStorage = storage
        } operation: {
            DraftAutoSaver(saveInterval: 60) // very long interval — rely on flush
        }

        await saver.registerEdit(sessionId: sessionId, content: "a: b", isDirty: true)
        await saver.flush(sessionId: sessionId)

        let drafts = await storage.savedDrafts
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.editorSessionId, sessionId)
    }

    func test_flush_nonDirtyEdit_producesNoDraft() async throws {
        let storage = FakeDraftStoragePort()
        let sessionId = UUID()

        let saver = withDependencies {
            $0.draftStorage = storage
        } operation: {
            DraftAutoSaver(saveInterval: 60)
        }

        await saver.registerEdit(sessionId: sessionId, content: "a: b", isDirty: false)
        await saver.flush(sessionId: sessionId)

        let drafts = await storage.savedDrafts
        XCTAssertTrue(drafts.isEmpty)
    }

    func test_flush_withoutPriorEdit_isNoOp() async throws {
        let storage = FakeDraftStoragePort()

        let saver = withDependencies {
            $0.draftStorage = storage
        } operation: {
            DraftAutoSaver()
        }

        await saver.flush(sessionId: UUID())
        let drafts = await storage.savedDrafts
        XCTAssertTrue(drafts.isEmpty)
    }
}

final class DraftAutoSaverSecretRedactionTests: XCTestCase {

    func test_flush_secretKind_marksRedacted() async throws {
        let storage = FakeDraftStoragePort()
        let sessionId = UUID()
        let ref = ResourceRef(apiVersion: "v1", kind: "Secret", namespace: "default", name: "my-secret")
        let secretYAML = "data:\n  key: c2VjcmV0\nstringData:\n  pass: plaintext"

        let saver = withDependencies {
            $0.draftStorage = storage
        } operation: {
            DraftAutoSaver(saveInterval: 60)
        }

        await saver.registerEdit(
            sessionId: sessionId,
            content: secretYAML,
            resourceRef: ref,
            sourceFormat: .yaml,
            isDirty: true
        )
        await saver.flush(sessionId: sessionId)

        let drafts = await storage.savedDrafts
        XCTAssertTrue(drafts.first?.sensitiveContentRedacted == true)
        XCTAssertFalse(drafts.first?.content.contains("c2VjcmV0") == true,
                       "Raw secret data must be redacted before persistence")
    }

    func test_flush_nonSecretKind_doesNotRedact() async throws {
        let storage = FakeDraftStoragePort()
        let sessionId = UUID()
        let ref = ResourceRef(apiVersion: "v1", kind: "ConfigMap", namespace: "default", name: "cm")

        let saver = withDependencies {
            $0.draftStorage = storage
        } operation: {
            DraftAutoSaver(saveInterval: 60)
        }

        await saver.registerEdit(
            sessionId: sessionId,
            content: "data:\n  key: value",
            resourceRef: ref,
            sourceFormat: .yaml,
            isDirty: true
        )
        await saver.flush(sessionId: sessionId)

        let drafts = await storage.savedDrafts
        XCTAssertFalse(drafts.first?.sensitiveContentRedacted == true)
    }
}
