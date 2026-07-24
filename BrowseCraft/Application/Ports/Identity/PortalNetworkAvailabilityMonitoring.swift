import Foundation

protocol PortalNetworkAvailabilityMonitoring: Sendable {
    func statusUpdates() -> AsyncStream<Bool>
}
