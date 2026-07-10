import Foundation

// 中文注释：SyncStateRepository 保存云同步进度书签，例如 CloudKit change token。
protocol SyncStateRepository {
    func fetchState(scope: String, zoneName: String) throws -> SyncState?
    func saveState(_ state: SyncState) throws
}
