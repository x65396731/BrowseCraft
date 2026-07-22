import Foundation
@testable import BrowseCraft

actor MockCloudAccountStateProvider: CloudAccountStateProviding {
    private var state: CloudAccountState
    private var continuations: [UUID: AsyncStream<CloudAccountState>.Continuation] = [:]
    private var startMonitoringCalls: Int = 0
    private var refreshCalls: Int = 0

    init(state: CloudAccountState = .initial) {
        self.state = state
    }

    func currentState() async -> CloudAccountState {
        return self.state
    }

    func stateUpdates() async -> AsyncStream<CloudAccountState> {
        let id: UUID = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.yield(self.state)
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    func startMonitoring() async {
        self.startMonitoringCalls += 1
    }

    func stopMonitoring() async {}

    func refresh() async {
        self.refreshCalls += 1
    }

    func startMonitoringCallCount() -> Int {
        return self.startMonitoringCalls
    }

    func refreshCallCount() -> Int {
        return self.refreshCalls
    }

    func setState(_ state: CloudAccountState) {
        self.state = state
        for continuation: AsyncStream<CloudAccountState>.Continuation in self.continuations.values {
            continuation.yield(state)
        }
    }

    private func removeContinuation(id: UUID) {
        self.continuations.removeValue(forKey: id)
    }
}

final class MockCloudSyncPreferenceStore: CloudSyncPreferenceStoring, @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var values: [CloudAccountScope: Bool] = [:]
    private var userConsent: Bool = false

    func hasCloudSyncUserConsent() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.userConsent
    }

    func setCloudSyncUserConsent(_ consented: Bool) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.userConsent = consented
    }

    func isCloudSyncEnabled(for scope: CloudAccountScope) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.values[scope] ?? false
    }

    func setCloudSyncEnabled(_ enabled: Bool, for scope: CloudAccountScope) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.values[scope] = enabled
    }
}
