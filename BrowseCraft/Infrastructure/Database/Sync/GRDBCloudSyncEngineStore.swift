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
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let userContext: CloudSyncUserContext?

    init(
        database: AppDatabase,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        userContext: CloudSyncUserContext? = nil
    ) {
        self.database = database
        self.activeAppUser = activeAppUser
        self.userContext = userContext
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
        let userID: String = self.currentUserID
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
                    .filter(SourceRecord.Columns.userID == userID)
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
                    .filter(FavoriteItemRecord.Columns.userID == userID)
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
                try database.execute(
                    sql: """
                    DELETE FROM \(SourceRecord.databaseTableName)
                    WHERE userID = ? AND id NOT LIKE 'built-in.%'
                    """,
                    arguments: [userID]
                )
                _ = try FavoriteItemRecord
                    .filter(FavoriteItemRecord.Columns.userID == userID)
                    .deleteAll(database)
                _ = try FavoriteRecord
                    .filter(FavoriteRecord.Columns.userID == userID)
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
            var record: CloudRecordMetadataRecord = CloudRecordMetadataRecord(
                accountScope: accountScope.rawValue,
                recordName: recordName,
                systemFields: data,
                updatedAt: Date()
            )
            try record.save(database)
        }
    }

    private var currentUserID: String {
        if let synchronizedUserID: UUID = self.userContext?.currentUserID {
            return synchronizedUserID.uuidString
        }
        return self.activeAppUser?.currentUserID.uuidString ?? AppUser.localDefaultID
    }
}
