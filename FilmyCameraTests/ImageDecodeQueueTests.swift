import Foundation
import XCTest
@testable import FilmyCamera

final class ImageDecodeQueueTests: XCTestCase, @unchecked Sendable {
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var active = 0
        private var peak = 0
        private var started = 0

        func enter() -> Int {
            lock.lock()
            defer { lock.unlock() }
            active += 1
            started += 1
            peak = max(peak, active)
            return started
        }

        func leave() {
            lock.lock()
            active -= 1
            lock.unlock()
        }

        func counts() -> (peak: Int, started: Int) {
            lock.lock()
            defer { lock.unlock() }
            return (peak, started)
        }
    }

    func testDecodeRunsOffMainThreadAndReturnsItsResult() async {
        let result = await ImageDecodeQueue().value {
            XCTAssertFalse(Thread.isMainThread)
            return 42
        }
        XCTAssertEqual(result, 42)
    }

    func testFailedDecodeReturnsNil() async {
        let result: Int? = await ImageDecodeQueue().value { nil }
        XCTAssertNil(result)
    }

    func testCancellationBeforeRegistrationNeverStartsDecode() async {
        let queue = ImageDecodeQueue()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await queue.value {
                XCTFail("An already-cancelled request must not decode")
                return 1
            }
        }
        let result = await task.value
        XCTAssertNil(result)
    }

    func testCancellationOfQueuedDecodeResumesWithoutWaitingForAWorker() async throws {
        let operations = OperationQueue()
        operations.isSuspended = true
        let queue = ImageDecodeQueue(queue: operations)
        defer { operations.isSuspended = false }
        let task = Task {
            await queue.value {
                XCTFail("A cancelled queued decode ran")
                return 1
            }
        }
        for _ in 0..<1_000 where operations.operationCount == 0 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(operations.operationCount, 1)
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
        let drained = expectation(description: "Cancelled operations are drained")
        operations.addBarrierBlock { drained.fulfill() }
        operations.isSuspended = false
        await fulfillment(of: [drained], timeout: 5)
    }

    func testCancellationDropsAnInFlightResultAndResumesBeforeDecodeCompletes() async {
        let queue = ImageDecodeQueue()
        let entered = expectation(description: "Decode entered")
        let finished = expectation(description: "Decode released")
        let release = DispatchSemaphore(value: 0)
        let task = Task {
            await queue.value {
                entered.fulfill()
                _ = release.wait(timeout: .now() + 5)
                finished.fulfill()
                return 99
            }
        }
        await fulfillment(of: [entered], timeout: 5)
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
        release.signal()
        await fulfillment(of: [finished], timeout: 5)
    }

    func testConcurrentDecodesNeverExceedTwoWorkers() async {
        let queue = ImageDecodeQueue(maximumConcurrentDecodes: 2)
        let probe = Probe()
        let firstWorkers = expectation(description: "Two workers started")
        firstWorkers.expectedFulfillmentCount = 2
        let release = DispatchSemaphore(value: 0)
        let batch = Task {
            await withTaskGroup(of: Int?.self, returning: [Int].self) { group in
                for index in 0..<12 {
                    group.addTask {
                        await queue.value {
                            if probe.enter() <= 2 { firstWorkers.fulfill() }
                            _ = release.wait(timeout: .now() + 5)
                            probe.leave()
                            return index
                        }
                    }
                }
                var results: [Int] = []
                for await value in group { if let value { results.append(value) } }
                return results
            }
        }
        await fulfillment(of: [firstWorkers], timeout: 5)
        XCTAssertEqual(probe.counts().started, 2)
        for _ in 0..<12 { release.signal() }
        let values = await batch.value
        XCTAssertEqual(values.sorted(), Array(0..<12))
        XCTAssertEqual(probe.counts().peak, 2)
    }

    func testCompletionCancellationRacesResumeExactlyOnce() async {
        let queue = ImageDecodeQueue()
        let tasks = (0..<300).map { index in
            Task { await queue.value { index } }
        }
        for (index, task) in tasks.enumerated() where index.isMultiple(of: 2) { task.cancel() }
        for (index, task) in tasks.enumerated() {
            let value = await task.value
            // Either completion or cancellation may win, but a stale result
            // must never be delivered to a different request or resumed twice.
            if let value { XCTAssertEqual(value, index) }
            if !index.isMultiple(of: 2) { XCTAssertEqual(value, index) }
        }
    }
}
