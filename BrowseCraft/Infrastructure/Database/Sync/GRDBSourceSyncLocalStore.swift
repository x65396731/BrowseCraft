import Foundation
import GRDB

final class GRDBSourceSyncLocalStore: SourceSyncLocalStore {
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
        for sourceIDs: [String]
    ) throws -> [String: SourceSyncLocalSnapshot] {
        return try self.database.queue.read { database in
            var snapshots: [String: SourceSyncLocalSnapshot] = [:]
            for sourceID: String in Set(sourceIDs) {
                guard let record: SourceRecord = try SourceRecord.fetchOne(
                    database,
                    key: ["userID": accountScope.rawValue, "id": sourceID]
                ) else {
                    continue
                }
                snapshots[sourceID] = SourceSyncLocalSnapshot(
                    sourceID: sourceID,
                    lastChangedAt: record.lastChangedAt,
                    isDeleted: record.deletedAt != nil
                )
            }
            return snapshots
        }
    }

    func commit(
        _ plan: SourceSyncMergePlan,
        accountScope: CloudAccountScope,
        scope: String,
        zoneName: String
    ) throws {
        try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: accountScope.rawValue, in: database)
            for payload: SourceCloudPayload in plan.acceptedPayloads {
                var scopedPayload: SourceCloudPayload = payload
                scopedPayload.userID = accountScope.rawValue
                var record: SourceRecord = SourceRecord(payload: scopedPayload)
                try record.save(database)
            }

            for change: SourceSyncLocalChange in plan.requeuedLocalChanges {
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .source,
                    entityID: change.sourceID,
                    operation: change.operation,
                    updatedAt: change.updatedAt,
                    in: database
                )
            }

            try Self.saveChangeToken(
                plan.changeToken,
                accountScope: accountScope,
                scope: scope,
                zoneName: zoneName,
                in: database
            )
        }
    }

    func pendingUploads(accountScope: CloudAccountScope) throws -> [SourceSyncPendingUpload] {
        return try self.database.queue.read { database in
            let queueRecords: [SyncQueueRecord] = try SyncQueueRecord
                .filter(SyncQueueRecord.Columns.accountScope == accountScope.rawValue)
                .filter(SyncQueueRecord.Columns.entityType == SyncEntityType.source.rawValue)
                .fetchAll(database)

            return try queueRecords.map { queueRecord in
                let sourceRecord: SourceRecord? = try SourceRecord.fetchOne(
                    database,
                    key: ["userID": accountScope.rawValue, "id": queueRecord.entityID]
                )
                return SourceSyncPendingUpload(
                    queueItem: queueRecord.domainModel(),
                    payload: sourceRecord.map { SourceCloudPayload(record: $0) }
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
