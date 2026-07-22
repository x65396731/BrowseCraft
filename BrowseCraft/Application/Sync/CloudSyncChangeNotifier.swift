import Foundation

final class CloudSyncChangeNotifier: CloudSyncChangeNotifying, @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    func notifyLocalChange() {
        self.lock.lock()
        let current: [AsyncStream<Void>.Continuation] = Array(self.continuations.values)
        self.lock.unlock()
        for continuation: AsyncStream<Void>.Continuation in current {
            continuation.yield(())
        }
    }

    func changes() -> AsyncStream<Void> {
        let id: UUID = UUID()
        return AsyncStream { continuation in
            self.lock.lock()
            self.continuations[id] = continuation
            self.lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    private func removeContinuation(id: UUID) {
        self.lock.lock()
        self.continuations.removeValue(forKey: id)
        self.lock.unlock()
    }
}
