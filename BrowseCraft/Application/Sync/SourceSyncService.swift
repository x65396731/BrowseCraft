import Foundation
import GRDB

// 中文注释：CloudSyncService 是同步用例入口；当前只实现 Source mock 同步。
protocol CloudSyncService {
    func syncSources(limit: Int) throws -> SourceSyncResult
}

struct SourceSyncResult: Hashable {
    var uploadedCount: Int
    var downloadedCount: Int
    var deletedCount: Int
    var skippedCount: Int
}

final class SourceSyncService: CloudSyncService {
    private let database: AppDatabase
    private let cloudStore: CloudRecordStore
    private let scope: String
    private let zoneName: String

    init(
        database: AppDatabase,
        cloudStore: CloudRecordStore,
        scope: String = "private",
        zoneName: String = "BrowseCraftSources"
    ) {
        self.database = database
        self.cloudStore = cloudStore
        self.scope = scope
        self.zoneName = zoneName
    }

    func syncSources(limit: Int = 100) throws -> SourceSyncResult {
        var result: SourceSyncResult = SourceSyncResult(
            uploadedCount: 0,
            downloadedCount: 0,
            deletedCount: 0,
            skippedCount: 0
        )

        let changeSet: SourceCloudChangeSet = try self.fetchCloudChanges()
        let mergeResult: SourceMergeResult = try self.mergeCloudChanges(changeSet)
        result.downloadedCount += mergeResult.downloadedCount
        result.deletedCount += mergeResult.deletedCount
        result.skippedCount += mergeResult.skippedCount

        let uploadResult: SourceUploadResult = try self.uploadPendingSourceChanges(limit: limit)
        result.uploadedCount += uploadResult.uploadedCount
        result.skippedCount += uploadResult.skippedCount

        return result
    }

    private func fetchCloudChanges() throws -> SourceCloudChangeSet {
        let token: Data? = try self.database.queue.read { database in
            return try SyncStateRecord
                .filter(
                    SyncStateRecord.Columns.scope == self.scope &&
                    SyncStateRecord.Columns.zoneName == self.zoneName
                )
                .fetchOne(database)?
                .serverChangeTokenData
        }

        return try self.cloudStore.fetchChangedSourceRecords(since: token)
    }

    private func mergeCloudChanges(_ changeSet: SourceCloudChangeSet) throws -> SourceMergeResult {
        return try self.database.queue.write { database in
            var result: SourceMergeResult = SourceMergeResult()

            for payload in changeSet.records {
                guard payload.isBuiltIn == false,
                      payload.userID == AppUser.localDefaultID,
                      payload.schemaVersion <= SourceCloudPayload.currentSchemaVersion,
                      payload.isUnsupportedVideoV1 == false else {
                    result.skippedCount += 1
                    continue
                }

                let existing: SourceRecord? = try SourceRecord.fetchOne(database, key: payload.sourceID)
                if let existing: SourceRecord {
                    if payload.lastChangedAt >= existing.lastChangedAt {
                        var record: SourceRecord = SourceRecord(payload: payload)
                        try record.save(database)
                        if payload.isDeleted {
                            result.deletedCount += 1
                        } else {
                            result.downloadedCount += 1
                        }
                    } else {
                        try SyncQueueRecord.enqueue(
                            entityType: .source,
                            entityID: existing.id,
                            operation: existing.deletedAt == nil ? .upsert : .delete,
                            updatedAt: existing.lastChangedAt,
                            in: database
                        )
                        result.skippedCount += 1
                    }
                } else {
                    var record: SourceRecord = SourceRecord(payload: payload)
                    try record.insert(database)
                    if payload.isDeleted {
                        result.deletedCount += 1
                    } else {
                        result.downloadedCount += 1
                    }
                }
            }

            if let token: Data = changeSet.changeToken {
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

            return result
        }
    }

    private func uploadPendingSourceChanges(limit: Int) throws -> SourceUploadResult {
        guard limit > 0 else {
            return SourceUploadResult(uploadedCount: 0, skippedCount: 0)
        }

        let pending: [SyncQueueItem] = try self.database.queue.read { database in
            let records: [SyncQueueRecord] = try SyncQueueRecord
                .filter(SyncQueueRecord.Columns.entityType == SyncEntityType.source.rawValue)
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

        let payloads: [SourceCloudPayload] = try self.database.queue.read { database in
            return try orderedPending.compactMap { item in
                guard let record: SourceRecord = try SourceRecord.fetchOne(database, key: item.entityID),
                      record.id.hasPrefix("built-in.") == false else {
                    return nil
                }

                return SourceCloudPayload(record: record)
            }
        }

        guard payloads.isEmpty == false else {
            return SourceUploadResult(uploadedCount: 0, skippedCount: orderedPending.count)
        }

        do {
            try self.cloudStore.saveSourceRecords(payloads)
        } catch {
            try self.markFailed(orderedPending, error: error)
            throw error
        }

        try self.database.queue.write { database in
            for item in orderedPending {
                _ = try SyncQueueRecord.deleteOne(database, key: item.id)
            }
        }

        return SourceUploadResult(
            uploadedCount: payloads.count,
            skippedCount: orderedPending.count - payloads.count
        )
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

private struct SourceMergeResult {
    var downloadedCount: Int = 0
    var deletedCount: Int = 0
    var skippedCount: Int = 0
}

private struct SourceUploadResult {
    var uploadedCount: Int
    var skippedCount: Int
}
