import Foundation
import GRDB

// 中文注释：SyncQueueRecord 是 sync_queue 表的一行，用于记录本地待上传变化。
struct SyncQueueRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName: String = "sync_queue"

    var id: String
    var entityType: String
    var entityID: String
    var operation: String
    var updatedAt: Date
    var retryCount: Int
    var lastError: String?
    var createdAt: Date

    init(item: SyncQueueItem) {
        self.id = item.id
        self.entityType = item.entityType.rawValue
        self.entityID = item.entityID
        self.operation = item.operation.rawValue
        self.updatedAt = item.updatedAt
        self.retryCount = item.retryCount
        self.lastError = item.lastError
        self.createdAt = item.createdAt
    }

    func domainModel() -> SyncQueueItem {
        return SyncQueueItem(
            id: self.id,
            entityType: SyncEntityType(rawValue: self.entityType) ?? .source,
            entityID: self.entityID,
            operation: SyncQueueOperation(rawValue: self.operation) ?? .upsert,
            updatedAt: self.updatedAt,
            retryCount: self.retryCount,
            lastError: self.lastError,
            createdAt: self.createdAt
        )
    }

    static func enqueue(
        entityType: SyncEntityType,
        entityID: String,
        operation: SyncQueueOperation,
        updatedAt: Date,
        in database: Database
    ) throws {
        if var existing: SyncQueueRecord = try SyncQueueRecord
            .filter(
                Self.Columns.entityType == entityType.rawValue &&
                Self.Columns.entityID == entityID
            )
            .fetchOne(database) {
            let existingOperation: SyncQueueOperation = SyncQueueOperation(rawValue: existing.operation) ?? .upsert
            if existingOperation == .delete,
               operation == .upsert,
               updatedAt <= existing.updatedAt {
                return
            }

            existing.operation = operation.rawValue
            existing.updatedAt = updatedAt
            existing.retryCount = 0
            existing.lastError = nil
            try existing.save(database)
            return
        }

        let item: SyncQueueItem = SyncQueueItem(
            id: SyncQueueItem.makeID(entityType: entityType, entityID: entityID),
            entityType: entityType,
            entityID: entityID,
            operation: operation,
            updatedAt: updatedAt,
            retryCount: 0,
            lastError: nil,
            createdAt: updatedAt
        )
        var record: SyncQueueRecord = SyncQueueRecord(item: item)
        try record.insert(database)
    }
}
