import Foundation
import GRDB

final class GRDBFavoriteItemSyncLocalStore: FavoriteItemSyncLocalStore {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func changeToken(scope: String, zoneName: String) throws -> Data? {
        return try self.database.queue.read { database in
            try SyncStateRecord
                .filter(
                    SyncStateRecord.Columns.scope == scope &&
                    SyncStateRecord.Columns.zoneName == zoneName
                )
                .fetchOne(database)?
                .serverChangeTokenData
        }
    }

    func snapshots(
        for keys: [FavoriteItemSyncKey]
    ) throws -> [FavoriteItemSyncKey: FavoriteItemSyncLocalSnapshot] {
        return try self.database.queue.read { database in
            var snapshots: [FavoriteItemSyncKey: FavoriteItemSyncLocalSnapshot] = [:]
            for key: FavoriteItemSyncKey in Set(keys) {
                guard let record: FavoriteItemRecord = try FavoriteItemRecord.fetchOne(
                    database,
                    key: ["userID": key.userID, "itemID": key.itemID]
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

    func commit(_ plan: FavoriteItemSyncMergePlan, scope: String, zoneName: String) throws {
        try self.database.queue.write { database in
            for payload: FavoriteItemCloudPayload in plan.acceptedPayloads {
                let key: [String: String] = [
                    "userID": payload.userID,
                    "itemID": payload.itemID
                ]
                let existing: FavoriteItemRecord? = try FavoriteItemRecord.fetchOne(database, key: key)
                var record: FavoriteItemRecord = FavoriteItemRecord(payload: payload)
                if let existing: FavoriteItemRecord {
                    record.createdAt = existing.createdAt
                }
                try record.save(database)
            }

            for change: FavoriteItemSyncLocalChange in plan.requeuedLocalChanges {
                try SyncQueueRecord.enqueue(
                    entityType: .favoriteItem,
                    entityID: change.itemID,
                    operation: change.operation,
                    updatedAt: change.updatedAt,
                    in: database
                )
            }

            try FavoriteAggregateBuilder.rebuild(userID: AppUser.localDefaultID, in: database)
            try Self.saveChangeToken(
                plan.changeToken,
                scope: scope,
                zoneName: zoneName,
                in: database
            )
        }
    }

    func pendingUploads(userID: String) throws -> [FavoriteItemSyncPendingUpload] {
        return try self.database.queue.read { database in
            let queueRecords: [SyncQueueRecord] = try SyncQueueRecord
                .filter(SyncQueueRecord.Columns.entityType == SyncEntityType.favoriteItem.rawValue)
                .fetchAll(database)

            return try queueRecords.map { queueRecord in
                let favoriteItemRecord: FavoriteItemRecord? = try FavoriteItemRecord.fetchOne(
                    database,
                    key: ["userID": userID, "itemID": queueRecord.entityID]
                )
                return FavoriteItemSyncPendingUpload(
                    queueItem: queueRecord.domainModel(),
                    payload: favoriteItemRecord.map { FavoriteItemCloudPayload(record: $0) }
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
