import Foundation
import GRDB

// 中文注释：GRDBSyncQueueRepository 保存本地待同步队列，供未来 CloudKit 同步器消费。
final class GRDBSyncQueueRepository: SyncQueueRepository {
    private let database: AppDatabase
    private let accountScopeProvider: any ActiveAccountScopeProviding

    init(
        database: AppDatabase,
        accountScopeProvider: any ActiveAccountScopeProviding = ActiveAccountScopeStore()
    ) {
        self.database = database
        self.accountScopeProvider = accountScopeProvider
    }

    func enqueue(entityType: SyncEntityType, entityID: String, operation: SyncQueueOperation) throws {
        let now: Date = Date()
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope

        try self.database.queue.write { database in
            try SyncQueueRecord.enqueue(
                accountScope: accountScope,
                entityType: entityType,
                entityID: entityID,
                operation: operation,
                updatedAt: now,
                in: database
            )
        }
    }

    func fetchPending(limit: Int) throws -> [SyncQueueItem] {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        return try self.database.queue.read { database in
            let records: [SyncQueueRecord] = try SyncQueueRecord
                .filter(SyncQueueRecord.Columns.accountScope == accountScope.rawValue)
                .order(SyncQueueRecord.Columns.updatedAt.asc)
                .limit(limit)
                .fetchAll(database)

            return records.map { record in
                return record.domainModel()
            }
        }
    }

    func markSynced(id: String) throws {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        try self.database.queue.write { database in
            _ = try SyncQueueRecord
                .filter(SyncQueueRecord.Columns.id == id)
                .filter(SyncQueueRecord.Columns.accountScope == accountScope.rawValue)
                .deleteAll(database)
        }
    }

    func markFailed(id: String, errorMessage: String) throws {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        try self.database.queue.write { database in
            guard var record: SyncQueueRecord = try SyncQueueRecord
                .filter(SyncQueueRecord.Columns.id == id)
                .filter(SyncQueueRecord.Columns.accountScope == accountScope.rawValue)
                .fetchOne(database) else {
                return
            }

            record.retryCount += 1
            record.lastError = errorMessage
            record.nextRetryAt = nil
            try record.save(database)
        }
    }
}
