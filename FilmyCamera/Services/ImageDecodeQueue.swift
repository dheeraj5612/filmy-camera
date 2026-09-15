import Foundation

/// Bounds blocking ImageIO work without blocking Swift's cooperative executor.
/// Cancellation resumes the caller immediately, skips queued decodes, and drops
/// the result of an already-running decode (ImageIO itself is not preemptible).
final class ImageDecodeQueue: @unchecked Sendable {
    static let shared = ImageDecodeQueue()
    private let queue: OperationQueue

    init(maximumConcurrentDecodes: Int = 2, queue: OperationQueue = OperationQueue()) {
        self.queue = queue
        queue.name = "com.filmycamera.image-decode"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = max(1, maximumConcurrentDecodes)
    }

    func value<Value: Sendable>(work: @escaping @Sendable () -> Value?) async -> Value? {
        let request = Request<Value>()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                guard request.install(continuation) else { return }
                let operation = BlockOperation {
                    guard request.begin() else { return }
                    #if canImport(ObjectiveC)
                    let result = autoreleasepool(invoking: work)
                    #else
                    let result = work()
                    #endif
                    request.finish(result)
                }
                request.install(operation)
                queue.addOperation(operation)
            }
        }, onCancel: {
            request.finish(nil, cancelling: true)
        })
    }

    private final class Request<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value?, Never>?
        private var operation: Operation?
        private var finished = false

        func install(_ continuation: CheckedContinuation<Value?, Never>) -> Bool {
            lock.lock()
            let accepts = !finished
            if accepts { self.continuation = continuation }
            lock.unlock()
            if !accepts { continuation.resume(returning: nil) }
            return accepts
        }

        func install(_ operation: Operation) {
            lock.lock()
            let shouldCancel = finished
            if !shouldCancel { self.operation = operation }
            lock.unlock()
            if shouldCancel { operation.cancel() }
        }

        func begin() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return !finished
        }

        func finish(_ value: Value?, cancelling: Bool = false) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            let continuation = self.continuation
            let operation = self.operation
            self.continuation = nil
            self.operation = nil
            lock.unlock()
            // Never call framework callbacks or resume a task while locked.
            if cancelling { operation?.cancel() }
            continuation?.resume(returning: value)
        }
    }
}
