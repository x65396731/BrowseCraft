import Foundation
import GRDB

final class GRDBCloudSyncEngineStore:
    CloudSyncEngineStateStoring,
    CloudRecordMetadataStoring,
    CloudRecordZoneRecoveryStoring,
    CloudSyncRetryScheduleProviding,
    @unchecked Sendable
{
    private static let stateScope: String = "private"
    private static let stateZoneName: String = "BrowseCraftSyncEngine"

    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func loadState(for accountScope: CloudAccountScope) throws -> Data? {
        return try self.database.queue.read { database in
            return try SyncStateRecord
                .filter(
                    SyncStateRecord.Columns.accountScope == accountScope.rawValue &&
                    SyncStateRecord.Columns.scope == Self.stateScope &&
                    SyncStateRecord.Columns.zoneName == Self.stateZoneName
                )
                .fetchOne(database)?
                .serverChangeTokenData
        }
    }

    func saveState(_ data: Data, for accountScope: CloudAccountScope) throws {
        try self.database.queue.write { database in
            let now: Date = Date()
            try AppUserRecord.insertUser(id: accountScope.rawValue, in: database)
            var record: SyncStateRecord = SyncStateRecord(
                state: SyncState(
                    accountScope: accountScope,
                    scope: Self.stateScope,
                    zoneName: Self.stateZoneName,
                    serverChangeTokenData: data,
                    lastSyncedAt: now,
                    updatedAt: now
                )
            )
            try record.save(database)
        }
    }

    func clearState(for accountScope: CloudAccountScope) throws {
        try self.database.queue.write { database in
            _ = try SyncStateRecord
                .filter(
                    SyncStateRecord.Columns.accountScope == accountScope.rawValue &&
                    SyncStateRecord.Columns.scope == Self.stateScope &&
                    SyncStateRecord.Columns.zoneName == Self.stateZoneName
                )
                .deleteAll(database)
        }
    }

    func recoverDeletedZone(
        for accountScope: CloudAccountScope,
        strategy: CloudRecordZoneRecoveryStrategy
    ) throws {
        try self.database.queue.write { database in
            _ = try SyncStateRecord
                .filter(SyncStateRecord.Columns.accountScope == accountScope.rawValue)
                .deleteAll(database)
            _ = try CloudRecordMetadataRecord
                .filter(CloudRecordMetadataRecord.Columns.accountScope == accountScope.rawValue)
                .deleteAll(database)
            _ = try SyncQueueRecord
                .filter(SyncQueueRecord.Columns.accountScope == accountScope.rawValue)
                .deleteAll(database)

            switch strategy {
            case .rebuildFromLocalData:
                let sources: [SourceRecord] = try SourceRecord
                    .filter(SourceRecord.Columns.userID == accountScope.rawValue)
                    .filter(SourceRecord.Columns.deletedAt == nil)
                    .fetchAll(database)
                for source: SourceRecord in sources where source.id.hasPrefix("built-in.") == false {
                    try SyncQueueRecord.enqueue(
                        accountScope: accountScope,
                        entityType: .source,
                        entityID: source.id,
                        operation: .upsert,
                        updatedAt: source.updatedAt,
                        in: database
                    )
                }

                let favoriteItems: [FavoriteItemRecord] = try FavoriteItemRecord
                    .filter(FavoriteItemRecord.Columns.userID == accountScope.rawValue)
                    .filter(FavoriteItemRecord.Columns.deletedAt == nil)
                    .fetchAll(database)
                for item: FavoriteItemRecord in favoriteItems {
                    try SyncQueueRecord.enqueue(
                        accountScope: accountScope,
                        entityType: .favoriteItem,
                        entityID: FavoriteItemIdentity(
                            sourceID: item.sourceID,
                            itemID: item.itemID
                        ).syncEntityID,
                        operation: .upsert,
                        updatedAt: item.updatedAt,
                        in: database
                    )
                }

            case .purgeLocalCloudData:
                _ = try SourceRecord
                    .filter(SourceRecord.Columns.userID == accountScope.rawValue)
                    .deleteAll(database)
                _ = try FavoriteItemRecord
                    .filter(FavoriteItemRecord.Columns.userID == accountScope.rawValue)
                    .deleteAll(database)
                _ = try FavoriteRecord
                    .filter(FavoriteRecord.Columns.userID == accountScope.rawValue)
                    .deleteAll(database)
            }
        }
    }

    func earliestRetryDate(for accountScope: CloudAccountScope) throws -> Date? {
        return try self.database.queue.read { database in
            try Date.fetchOne(
                database,
                sql: """
                SELECT MIN(nextRetryAt)
                FROM \(SyncQueueRecord.databaseTableName)
                WHERE accountScope = ? AND nextRetryAt IS NOT NULL
                """,
                arguments: [accountScope.rawValue]
            )
        }
    }

    func systemFields(
        accountScope: CloudAccountScope,
        recordName: String
    ) throws -> Data? {
        return try self.database.queue.read { database in
            return try CloudRecordMetadataRecord.fetchOne(
                database,
                key: [
                    "accountScope": accountScope.rawValue,
                    "recordName": recordName
                ]
            )?.systemFields
        }
    }

    func saveSystemFields(
        _ data: Data,
        accountScope: CloudAccountScope,
        recordName: String
    ) throws {
        try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: accountScope.rawValue, in: database)
            var record: CloudRecordMetadataRecord = CloudRecordMetadataRecord(
                accountScope: accountScope.rawValue,
                recordName: recordName,
                systemFields: data,
                updatedAt: Date()
            )
            try record.save(database)
        }
    }
}
