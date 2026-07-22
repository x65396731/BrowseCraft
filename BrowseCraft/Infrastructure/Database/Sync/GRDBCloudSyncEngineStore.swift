import Foundation
import GRDB

final class GRDBCloudSyncEngineStore:
    CloudSyncEngineStateStoring,
    CloudRecordMetadataStoring,
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
