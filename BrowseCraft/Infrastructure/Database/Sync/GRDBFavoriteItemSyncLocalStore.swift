import Foundation
import GRDB

final class GRDBFavoriteItemSyncLocalStore: FavoriteItemSyncLocalStore {
    private let database: AppDatabase
    private let now: () -> Date

    init(database: AppDatabase, now: @escaping () -> Date = Date.init) {
        self.database = database
        self.now = now
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
                    key: [
                        "userID": accountScope.rawValue,
                        "sourceID": key.sourceID,
                        "itemID": key.itemID
                    ]
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
        let partitionCounts: (live: Int, tombstone: Int) = try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: accountScope.rawValue, in: database)
            for payload: FavoriteItemCloudPayload in plan.acceptedPayloads {
                let key: [String: String] = [
                    "userID": accountScope.rawValue,
                    "sourceID": payload.sourceID,
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
                    entityID: FavoriteItemIdentity(
                        sourceID: change.sourceID,
                        itemID: change.itemID
                    ).syncEntityID,
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

            let liveCount: Int = try FavoriteItemRecord
                .filter(FavoriteItemRecord.Columns.userID == accountScope.rawValue)
                .filter(FavoriteItemRecord.Columns.deletedAt == nil)
                .fetchCount(database)
            let totalCount: Int = try FavoriteItemRecord
                .filter(FavoriteItemRecord.Columns.userID == accountScope.rawValue)
                .fetchCount(database)
            return (live: liveCount, tombstone: totalCount - liveCount)
        }
        CloudSyncDiagnostics.logLocalPartitionSummary(
            entityType: .favoriteItem,
            accountScope: accountScope,
            acceptedCount: plan.acceptedPayloads.count,
            requeuedCount: plan.requeuedLocalChanges.count,
            liveCount: partitionCounts.live,
            tombstoneCount: partitionCounts.tombstone
        )
    }

    func pendingUploads(accountScope: CloudAccountScope) throws -> [FavoriteItemSyncPendingUpload] {
        return try self.database.queue.read { database in
            let now: Date = self.now()
            let queueRecords: [SyncQueueRecord] = try SyncQueueRecord
                .filter(SyncQueueRecord.Columns.accountScope == accountScope.rawValue)
                .filter(SyncQueueRecord.Columns.entityType == SyncEntityType.favoriteItem.rawValue)
                .filter(
                    SyncQueueRecord.Columns.nextRetryAt == nil ||
                        SyncQueueRecord.Columns.nextRetryAt <= now
                )
                .fetchAll(database)

            return try queueRecords.map { queueRecord in
                let identity: FavoriteItemIdentity? = FavoriteItemIdentity(
                    syncEntityID: queueRecord.entityID
                )
                let favoriteItemRecord: FavoriteItemRecord?
                if let identity: FavoriteItemIdentity {
                    favoriteItemRecord = try FavoriteItemRecord.fetchOne(
                        database,
                        key: [
                            "userID": accountScope.rawValue,
                            "sourceID": identity.sourceID,
                            "itemID": identity.itemID
                        ]
                    )
                } else {
                    favoriteItemRecord = nil
                }
                return FavoriteItemSyncPendingUpload(
                    queueItem: queueRecord.domainModel(),
                    payload: try favoriteItemRecord.map { try FavoriteItemCloudPayload(record: $0) }
                )
            }
        }
    }

    func removePendingUploads(acknowledgements: [SyncQueueAcknowledgement]) throws {
        try self.database.queue.write { database in
            for acknowledgement: SyncQueueAcknowledgement in acknowledgements {
                guard let record: SyncQueueRecord = try SyncQueueRecord.fetchOne(
                    database,
                    key: acknowledgement.id
                ),
                record.operation == acknowledgement.operation.rawValue,
                record.updatedAt == acknowledgement.updatedAt else {
                    continue
                }
                _ = try SyncQueueRecord.deleteOne(database, key: acknowledgement.id)
            }
        }
    }

    func markPendingUploadsFailed(_ updates: [SyncQueueFailureUpdate]) throws {
        try self.database.queue.write { database in
            let failedAt: Date = self.now()
            for update: SyncQueueFailureUpdate in updates {
                let acknowledgement: SyncQueueAcknowledgement = update.acknowledgement
                guard var record: SyncQueueRecord = try SyncQueueRecord.fetchOne(
                    database,
                    key: acknowledgement.id
                ),
                record.operation == acknowledgement.operation.rawValue,
                record.updatedAt == acknowledgement.updatedAt else {
                    continue
                }
                record.retryCount += 1
                record.lastError = update.errorMessage
                record.nextRetryAt = update.retryAfter.flatMap { retryAfter in
                    CloudSyncAutomaticRetryPolicy.delay(
                        forFailureCount: record.retryCount,
                        serverRetryAfter: retryAfter
                    ).map {
                        failedAt.addingTimeInterval($0)
                    }
                }
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
