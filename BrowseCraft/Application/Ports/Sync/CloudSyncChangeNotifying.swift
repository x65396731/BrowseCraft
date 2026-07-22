import Foundation

protocol CloudSyncChangeNotifying: Sendable {
    func notifyLocalChange()
    func changes() -> AsyncStream<Void>
}
