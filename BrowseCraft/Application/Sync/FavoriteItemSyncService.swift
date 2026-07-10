import Foundation
import GRDB

// 中文注释：FavoriteItemSyncService 只同步 favorite_items 明细，不直接同步 favorites 聚合 JSON。
final class FavoriteItemSyncService {
    private let database: AppDatabase
    private let cloudStore: CloudRecordStore
    private let scope: String
    private let zoneName: String

    init(
        database: AppDatabase,
        cloudStore: CloudRecordStore,
        scope: String = "private",
        zoneName: String = "BrowseCraftFavoriteItems"
    ) {
        self.database = database
        self.cloudStore = cloudStore
        self.scope = scope
        self.zoneName = zoneName
    }

    func syncFavoriteItems(limit: Int = 100) throws -> FavoriteItemSyncResult {
        var result: FavoriteItemSyncResult = FavoriteItemSyncResult(
            uploadedCount: 0,
            downloadedCount: 0,
            deletedCount: 0,
            skippedCount: 0
        )

        let changeSet: FavoriteItemCloudChangeSet = try self.fetchCloudChanges()
        let mergeResult: FavoriteItemMergeResult = try self.mergeCloudChanges(changeSet)
        result.downloadedCount += mergeResult.downloadedCount
        result.deletedCount += mergeResult.deletedCount
        result.skippedCount += mergeResult.skippedCount

        let uploadResult: FavoriteItemUploadResult = try self.uploadPendingFavoriteItemChanges(limit: limit)
        result.uploadedCount += uploadResult.uploadedCount
        result.skippedCount += uploadResult.skippedCount

        return result
    }

    private func fetchCloudChanges() throws -> FavoriteItemCloudChangeSet {
        let token: Data? = try self.database.queue.read { database in
            return try SyncStateRecord
                .filter(
                    SyncStateRecord.Columns.scope == self.scope &&
                    SyncStateRecord.Columns.zoneName == self.zoneName
                )
                .fetchOne(database)?
                .serverChangeTokenData
        }

        return try self.cloudStore.fetchChangedFavoriteItemRecords(since: token)
    }

    private func mergeCloudChanges(_ changeSet: FavoriteItemCloudChangeSet) throws -> FavoriteItemMergeResult {
        return try self.database.queue.write { database in
            var result: FavoriteItemMergeResult = FavoriteItemMergeResult()

            for payload in changeSet.records {
                guard payload.userID == AppUser.localDefaultID,
                      payload.schemaVersion <= FavoriteItemCloudPayload.currentSchemaVersion else {
                    result.skippedCount += 1
                    continue
                }

                let existing: FavoriteItemRecord? = try FavoriteItemRecord.fetchOne(
                    database,
                    key: ["userID": payload.userID, "itemID": payload.itemID]
                )

                if let existing: FavoriteItemRecord {
                    if payload.lastChangedAt >= existing.lastChangedAt {
                        var record: FavoriteItemRecord = FavoriteItemRecord(payload: payload)
                        record.createdAt = existing.createdAt
                        try record.save(database)
                        if payload.isDeleted {
                            result.deletedCount += 1
                        } else {
                            result.downloadedCount += 1
                        }
                    } else {
                        try SyncQueueRecord.enqueue(
                            entityType: .favoriteItem,
                            entityID: existing.itemID,
                            operation: existing.deletedAt == nil ? .upsert : .delete,
                            updatedAt: existing.lastChangedAt,
                            in: database
                        )
                        result.skippedCount += 1
                    }
                } else {
                    var record: FavoriteItemRecord = FavoriteItemRecord(payload: payload)
                    try record.insert(database)
                    if payload.isDeleted {
                        result.deletedCount += 1
                    } else {
                        result.downloadedCount += 1
                    }
                }
            }

            try FavoriteAggregateBuilder.rebuild(userID: AppUser.localDefaultID, in: database)
            try self.saveChangeToken(changeSet.changeToken, in: database)
            return result
        }
    }

    private func uploadPendingFavoriteItemChanges(limit: Int) throws -> FavoriteItemUploadResult {
        guard limit > 0 else {
            return FavoriteItemUploadResult(uploadedCount: 0, skippedCount: 0)
        }

        let pending: [SyncQueueItem] = try self.database.queue.read { database in
            let records: [SyncQueueRecord] = try SyncQueueRecord
                .filter(SyncQueueRecord.Columns.entityType == SyncEntityType.favoriteItem.rawValue)
                .order(SyncQueueRecord.Columns.updatedAt.asc)
                .fetchAll(database)

            return records.map { record in
                return record.domainModel()
            }
        }

        let orderedPending: [SyncQueueItem] = Array(pending.sorted { lhs, rhs in
            if lhs.operation != rhs.operation {
                return lhs.operation == .delete
            }

            return lhs.updatedAt < rhs.updatedAt
        }.prefix(limit))

        let payloads: [FavoriteItemCloudPayload] = try self.database.queue.read { database in
            return try orderedPending.compactMap { item in
                guard let record: FavoriteItemRecord = try FavoriteItemRecord.fetchOne(
                    database,
                    key: ["userID": AppUser.localDefaultID, "itemID": item.entityID]
                ) else {
                    return nil
                }

                return FavoriteItemCloudPayload(record: record)
            }
        }

        guard payloads.isEmpty == false else {
            return FavoriteItemUploadResult(uploadedCount: 0, skippedCount: orderedPending.count)
        }

        do {
            try self.cloudStore.saveFavoriteItemRecords(payloads)
        } catch {
            try self.markFailed(orderedPending, error: error)
            throw error
        }

        try self.database.queue.write { database in
            for item in orderedPending {
                _ = try SyncQueueRecord.deleteOne(database, key: item.id)
            }
        }

        return FavoriteItemUploadResult(
            uploadedCount: payloads.count,
            skippedCount: orderedPending.count - payloads.count
        )
    }

    private func saveChangeToken(_ token: Data?, in database: Database) throws {
        guard let token: Data else {
            return
        }

        let now: Date = Date()
        var state: SyncStateRecord = SyncStateRecord(
            state: SyncState(
                scope: self.scope,
                zoneName: self.zoneName,
                serverChangeTokenData: token,
                lastSyncedAt: now,
                updatedAt: now
            )
        )
        try state.save(database)
    }

    private func markFailed(_ items: [SyncQueueItem], error: Error) throws {
        try self.database.queue.write { database in
            for item in items {
                guard var record: SyncQueueRecord = try SyncQueueRecord.fetchOne(database, key: item.id) else {
                    continue
                }

                record.retryCount += 1
                record.lastError = String(describing: error)
                record.updatedAt = Date()
                try record.save(database)
            }
        }
    }
}

struct FavoriteItemSyncResult: Hashable {
    var uploadedCount: Int
    var downloadedCount: Int
    var deletedCount: Int
    var skippedCount: Int
}

private struct FavoriteItemMergeResult {
    var downloadedCount: Int = 0
    var deletedCount: Int = 0
    var skippedCount: Int = 0
}

private struct FavoriteItemUploadResult {
    var uploadedCount: Int
    var skippedCount: Int
}
