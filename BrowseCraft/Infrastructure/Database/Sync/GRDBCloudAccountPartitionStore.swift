import Foundation
import GRDB

final class GRDBCloudAccountPartitionStore: CloudAccountPartitioning {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func localDefaultSummary() throws -> CloudAccountPartitionSummary {
        return try self.database.queue.read { database in
            let sourceRecords: [SourceRecord] = try SourceRecord
                .filter(SourceRecord.Columns.userID == CloudAccountScope.localDefault.rawValue)
                .fetchAll(database)
            let sourceCount: Int = sourceRecords.filter { record in
                return record.id.hasPrefix("built-in.") == false
            }.count
            let favoriteItemCount: Int = try FavoriteItemRecord
                .filter(FavoriteItemRecord.Columns.userID == CloudAccountScope.localDefault.rawValue)
                .fetchCount(database)
            return CloudAccountPartitionSummary(
                sourceCount: sourceCount,
                favoriteItemCount: favoriteItemCount
            )
        }
    }

    func prepareCloudScope(
        _ cloudScope: CloudAccountScope,
        decision: CloudAccountLocalDataDecision
    ) throws -> CloudAccountPartitionMergeResult {
        guard cloudScope.isCloud else {
            throw CloudAccountPartitionStoreError.invalidCloudScope
        }

        return try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: cloudScope.rawValue, in: database)

            switch decision {
            case .useCloudDataOnly:
                return CloudAccountPartitionMergeResult(
                    copiedSourceCount: 0,
                    copiedFavoriteItemCount: 0,
                    skippedCount: 0
                )

            case .mergeLocalData:
                let sourceResult: AccountPartitionCopyResult = try Self.copySources(
                    to: cloudScope,
                    in: database
                )
                let favoriteResult: AccountPartitionCopyResult = try Self.copyFavoriteItems(
                    to: cloudScope,
                    in: database
                )
                try FavoriteAggregateBuilder.rebuild(userID: cloudScope.rawValue, in: database)
                return CloudAccountPartitionMergeResult(
                    copiedSourceCount: sourceResult.copiedCount,
                    copiedFavoriteItemCount: favoriteResult.copiedCount,
                    skippedCount: sourceResult.skippedCount + favoriteResult.skippedCount
                )
            }
        }
    }

    private static func copySources(
        to cloudScope: CloudAccountScope,
        in database: Database
    ) throws -> AccountPartitionCopyResult {
        let localRecords: [SourceRecord] = try SourceRecord
            .filter(SourceRecord.Columns.userID == CloudAccountScope.localDefault.rawValue)
            .fetchAll(database)
        var result: AccountPartitionCopyResult = AccountPartitionCopyResult()

        for localRecord: SourceRecord in localRecords {
            guard localRecord.id.hasPrefix("built-in.") == false else {
                continue
            }
            let key: [String: String] = [
                "userID": cloudScope.rawValue,
                "id": localRecord.id
            ]
            let cloudRecord: SourceRecord? = try SourceRecord.fetchOne(database, key: key)
            guard Self.shouldCopy(
                localChangedAt: localRecord.lastChangedAt,
                localIsDeleted: localRecord.deletedAt != nil,
                targetChangedAt: cloudRecord?.lastChangedAt,
                targetIsDeleted: cloudRecord?.deletedAt != nil
            ) else {
                result.skippedCount += 1
                continue
            }

            var copiedRecord: SourceRecord = localRecord
            copiedRecord.userID = cloudScope.rawValue
            try copiedRecord.save(database)
            result.copiedCount += 1

            try SyncQueueRecord.enqueue(
                accountScope: cloudScope,
                entityType: .source,
                entityID: copiedRecord.id,
                operation: copiedRecord.deletedAt == nil ? .upsert : .delete,
                updatedAt: copiedRecord.lastChangedAt,
                in: database
            )
        }
        return result
    }

    private static func copyFavoriteItems(
        to cloudScope: CloudAccountScope,
        in database: Database
    ) throws -> AccountPartitionCopyResult {
        let localRecords: [FavoriteItemRecord] = try FavoriteItemRecord
            .filter(FavoriteItemRecord.Columns.userID == CloudAccountScope.localDefault.rawValue)
            .fetchAll(database)
        var result: AccountPartitionCopyResult = AccountPartitionCopyResult()

        for localRecord: FavoriteItemRecord in localRecords {
            let key: [String: String] = [
                "userID": cloudScope.rawValue,
                "itemID": localRecord.itemID
            ]
            let cloudRecord: FavoriteItemRecord? = try FavoriteItemRecord.fetchOne(database, key: key)
            guard Self.shouldCopy(
                localChangedAt: localRecord.lastChangedAt,
                localIsDeleted: localRecord.deletedAt != nil,
                targetChangedAt: cloudRecord?.lastChangedAt,
                targetIsDeleted: cloudRecord?.deletedAt != nil
            ) else {
                result.skippedCount += 1
                continue
            }
            guard var item: FavoriteContentItem = localRecord.favoriteItem() else {
                result.skippedCount += 1
                continue
            }

            if var snapshot: FavoriteSourceSnapshot = item.sourceSnapshot {
                snapshot.userID = cloudScope.rawValue
                item.sourceSnapshot = snapshot
            }
            var copiedRecord: FavoriteItemRecord = try FavoriteItemRecord(
                userID: cloudScope.rawValue,
                item: item,
                updatedAt: localRecord.updatedAt,
                deletedAt: localRecord.deletedAt
            )
            copiedRecord.createdAt = localRecord.createdAt
            try copiedRecord.save(database)
            result.copiedCount += 1

            try SyncQueueRecord.enqueue(
                accountScope: cloudScope,
                entityType: .favoriteItem,
                entityID: copiedRecord.itemID,
                operation: copiedRecord.deletedAt == nil ? .upsert : .delete,
                updatedAt: copiedRecord.lastChangedAt,
                in: database
            )
        }
        return result
    }

    private static func shouldCopy(
        localChangedAt: Date,
        localIsDeleted: Bool,
        targetChangedAt: Date?,
        targetIsDeleted: Bool
    ) -> Bool {
        guard let targetChangedAt: Date else {
            return true
        }
        if localChangedAt != targetChangedAt {
            return localChangedAt > targetChangedAt
        }
        return localIsDeleted && targetIsDeleted == false
    }
}

private struct AccountPartitionCopyResult {
    var copiedCount: Int = 0
    var skippedCount: Int = 0
}

private enum CloudAccountPartitionStoreError: Error {
    case invalidCloudScope
}
