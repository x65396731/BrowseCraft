import Foundation
import Network

/// 中文注释：只在网络从不可用恢复为可用时唤醒 Portal Session，不执行周期性后台请求。
final class NWPathPortalNetworkAvailabilityMonitor:
    PortalNetworkAvailabilityMonitoring,
    @unchecked Sendable {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue(label: "BrowseCraft.PortalNetworkAvailability")) {
        self.queue = queue
    }

    func statusUpdates() -> AsyncStream<Bool> {
        let monitor: NWPathMonitor = NWPathMonitor()
        return AsyncStream { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in
                monitor.cancel()
            }
            monitor.start(queue: self.queue)
        }
    }
}
