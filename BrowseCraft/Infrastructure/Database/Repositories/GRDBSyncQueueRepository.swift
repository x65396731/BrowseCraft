import Foundation
import GRDB

// 中文注释：GRDBSyncQueueRepository 保存本地待同步队列，供未来 CloudKit 同步器消费。
final class GRDBSyncQueueRepository: SyncQueueRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func enqueue(entityType: SyncEntityType, entityID: String, operation: SyncQueueOperation) throws {
        let now: Date = Date()

        try self.database.queue.write { database in
            try SyncQueueRecord.enqueue(
                entityType: entityType,
                entityID: entityID,
                operation: operation,
                updatedAt: now,
                in: database
            )
        }
    }

    func fetchPending(limit: Int) throws -> [SyncQueueItem] {
        return try self.database.queue.read { database in
            let records: [SyncQueueRecord] = try SyncQueueRecord
                .order(SyncQueueRecord.Columns.updatedAt.asc)
                .limit(limit)
                .fetchAll(database)

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    func markSynced(id: String) throws {
        try self.database.queue.write { database in
            _ = try SyncQueueRecord.deleteOne(database, key: id)
        }
    }

    func markFailed(id: String, errorMessage: String) throws {
        try self.database.queue.write { database in
            guard var record: SyncQueueRecord = try SyncQueueRecord.fetchOne(database, key: id) else {
                return
            }

            record.retryCount += 1
            record.lastError = errorMessage
            record.updatedAt = Date()
            try record.save(database)
        }
    }
}
