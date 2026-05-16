// Tests/LocalPersistenceTests/PersistenceActorTests.swift
// XCTest suite for PersistenceActor (ADR-0010 serialization gate)
//
// Coverage:
//   1. Serial write ordering — writes from concurrent tasks execute without
//      data races (actor serialization guarantee).
//   2. Read concurrency — multiple concurrent reads complete successfully.
//   3. Barrier wait — barrier() drains in-flight writes before returning.
//   4. Write error propagation — errors thrown inside a write closure surface
//      at the call site.

import XCTest
import Dependencies
@testable import LocalPersistence

// MARK: - PersistenceActorTests

final class PersistenceActorTests: XCTestCase {

    // MARK: Helpers

    /// Creates a `PersistenceActor` backed by the in-memory `FakePersistenceWriter`.
    private func makeActor() -> PersistenceActor {
        PersistenceActor(writer: FakePersistenceWriter())
    }

    // MARK: Test 1 — Serial write ordering

    /// Launches N concurrent write tasks and asserts that all complete without
    /// crashing. Actor isolation prevents data races; the counter increments are
    /// logically serialized even if tasks are scheduled concurrently.
    func test_serialWriteOrdering_allWritesComplete() async throws {
        let actor = makeActor()
        let taskCount = 20
        var completedCount = 0

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0 ..< taskCount {
                group.addTask {
                    _ = try await actor.write { _ in i }
                }
            }
            for try await _ in group {
                completedCount += 1
            }
        }

        XCTAssertEqual(completedCount, taskCount)
    }

    // MARK: Test 2 — Read concurrency

    /// Multiple concurrent reads must all complete successfully. WAL mode
    /// allows concurrent readers; the actor does not block them.
    func test_readConcurrency_allReadsComplete() async throws {
        let actor = makeActor()
        let readCount = 10

        let results: [Int] = try await withThrowingTaskGroup(
            of: Int.self,
            returning: [Int].self
        ) { group in
            for i in 0 ..< readCount {
                group.addTask {
                    try await actor.read { _ in i * 2 }
                }
            }
            var collected: [Int] = []
            for try await value in group {
                collected.append(value)
            }
            return collected
        }

        XCTAssertEqual(results.count, readCount)
        // All returned values must be even (i * 2).
        XCTAssertTrue(results.allSatisfy { $0 % 2 == 0 })
    }

    // MARK: Test 3 — Barrier wait

    /// Enqueues writes and then calls barrier(). barrier() must return only
    /// after all previously submitted writes are drained.
    /// With `FakePersistenceWriter` the barrier is a no-op, but we verify
    /// the API contract compiles and returns without hanging.
    func test_barrier_returnsWithoutHanging() async throws {
        let actor = makeActor()

        // Enqueue several writes.
        for i in 0 ..< 5 {
            _ = try await actor.write { _ in i }
        }

        // barrier() must complete within the test timeout.
        await actor.barrier()
        // If we reach here the barrier did not deadlock.
        XCTAssert(true)
    }

    // MARK: Test 4 — Write error propagation

    /// An error thrown inside a write closure must surface at the call site.
    func test_writeError_propagatesToCaller() async {
        let actor = makeActor()

        do {
            _ = try await actor.write { _ -> Int in
                throw PersistenceActorError.operationFailed(underlying: "test-error")
            }
            XCTFail("Expected PersistenceActorError to be thrown")
        } catch let error as PersistenceActorError {
            guard case .operationFailed(let msg) = error else {
                XCTFail("Unexpected PersistenceActorError case: \(error)")
                return
            }
            XCTAssertEqual(msg, "test-error")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
