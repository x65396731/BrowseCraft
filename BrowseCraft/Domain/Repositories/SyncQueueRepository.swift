import Foundation

// 中文注释：SyncQueueRepository 负责本地待上传队列，不负责真实云端传输。
protocol SyncQueueRepository {
    func enqueue(entityType: SyncEntityType, entityID: String, operation: SyncQueueOperation) throws
    func fetchPending(limit: Int) throws -> [SyncQueueItem]
    func markSynced(id: String) throws
    func markFailed(id: String, errorMessage: String) throws
}
