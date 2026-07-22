import Foundation
import GRDB

final class GRDBFavoriteItemSyncLocalStore: FavoriteItemSyncLocalStore {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func changeToken(
        accountScope: CloudAccountScope,
        scope: String,
        zoneName: String
    ) throws -> Data? {
        return try self.database.queue.read { database in
            try SyncStateRecord
                .filter(
                    SyncStateRecord.Columns.accountScope == accountScope.rawValue &&
                    SyncStateRecord.Columns.scope == scope &&
                    SyncStateRecord.Columns.zoneName == zoneName
                )
                .fetchOne(database)?
                .serverChangeTokenData
        }
    }

    func snapshots(
        accountScope: CloudAccountScope,
        for keys: [FavoriteItemSyncKey]
    ) throws -> [FavoriteItemSyncKey: FavoriteItemSyncLocalSnapshot] {
        return try self.database.queue.read { database in
            var snapshots: [FavoriteItemSyncKey: FavoriteItemSyncLocalSnapshot] = [:]
            for key: FavoriteItemSyncKey in Set(keys) {
                guard let record: FavoriteItemRecord = try FavoriteItemRecord.fetchOne(
                    database,
                    key: ["userID": accountScope.rawValue, "itemID": key.itemID]
                ) else {
                    continue
                }
                snapshots[key] = FavoriteItemSyncLocalSnapshot(
                    key: key,
                    lastChangedAt: record.lastChangedAt,
                    isDeleted: record.deletedAt != nil
                )
            }
            return snapshots
        }
    }

    func commit(
        _ plan: FavoriteItemSyncMergePlan,
        accountScope: CloudAccountScope,
        scope: String,
        zoneName: String
    ) throws {
        try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: accountScope.rawValue, in: database)
            for payload: FavoriteItemCloudPayload in plan.acceptedPayloads {
                let key: [String: String] = [
                    "userID": accountScope.rawValue,
                    "itemID": payload.itemID
                ]
                let existing: FavoriteItemRecord? = try FavoriteItemRecord.fetchOne(database, key: key)
                var scopedPayload: FavoriteItemCloudPayload = payload
                scopedPayload.userID = accountScope.rawValue
                var record: FavoriteItemRecord = try FavoriteItemRecord(payload: scopedPayload)
                if let existing: FavoriteItemRecord {
                    record.createdAt = existing.createdAt
                }
                try record.save(database)
            }

            for change: FavoriteItemSyncLocalChange in plan.requeuedLocalChanges {
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .favoriteItem,
                    entityID: change.itemID,
                    operation: change.operation,
                    updatedAt: change.updatedAt,
                    in: database
                )
            }

            try FavoriteAggregateBuilder.rebuild(userID: accountScope.rawValue, in: database)
            try Self.saveChangeToken(
                plan.changeToken,
                accountScope: accountScope,
                scope: scope,
                zoneName: zoneName,
                in: database
            )
        }
    }

    func pendingUploads(accountScope: CloudAccountScope) throws -> [FavoriteItemSyncPendingUpload] {
        return try self.database.queue.read { database in
            let queueRecords: [SyncQueueRecord] = try SyncQueueRecord
                .filter(SyncQueueRecord.Columns.accountScope == accountScope.rawValue)
                .filter(SyncQueueRecord.Columns.entityType == SyncEntityType.favoriteItem.rawValue)
                .fetchAll(database)

            return try queueRecords.map { queueRecord in
                let favoriteItemRecord: FavoriteItemRecord? = try FavoriteItemRecord.fetchOne(
                    database,
                    key: ["userID": accountScope.rawValue, "itemID": queueRecord.entityID]
                )
                return FavoriteItemSyncPendingUpload(
                    queueItem: queueRecord.domainModel(),
                    payload: try favoriteItemRecord.map { try FavoriteItemCloudPayload(record: $0) }
                )
            }
        }
    }

    func removePendingUploads(ids: [String]) throws {
        try self.database.queue.write { database in
            for id: String in ids {
                _ = try SyncQueueRecord.deleteOne(database, key: id)
            }
        }
    }

    func markPendingUploadsFailed(ids: [String], errorMessage: String) throws {
        try self.database.queue.write { database in
            let now: Date = Date()
            for id: String in ids {
                guard var record: SyncQueueRecord = try SyncQueueRecord.fetchOne(database, key: id) else {
                    continue
                }
                record.retryCount += 1
                record.lastError = errorMessage
                record.updatedAt = now
                try record.save(database)
            }
        }
    }

    private static func saveChangeToken(
        _ token: Data?,
        accountScope: CloudAccountScope,
        scope: String,
        zoneName: String,
        in database: Database
    ) throws {
        guard let token: Data else {
            return
        }
        let now: Date = Date()
        var state: SyncStateRecord = SyncStateRecord(
            state: SyncState(
                accountScope: accountScope,
                scope: scope,
                zoneName: zoneName,
                serverChangeTokenData: token,
                lastSyncedAt: now,
                updatedAt: now
            )
        )
        try state.save(database)
    }
}
