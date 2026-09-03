import Foundation
@preconcurrency import GRDB

final class GRDBCloudAccountPartitionStore:
    CloudAccountPartitioning,
    CloudAppUserAssociationAttestationStoring,
    @unchecked Sendable {
    private let database: AppDatabase
    private let activeAppUser: (any ActiveAppUserProviding)?

    init(
        database: AppDatabase,
        activeAppUser: (any ActiveAppUserProviding)? = nil
    ) {
        self.database = database
        self.activeAppUser = activeAppUser
    }

    func currentUserSummary() throws -> CloudAccountPartitionSummary {
        let userID: String = self.currentUserID
        return try self.database.queue.read { database in
            let sourceRecords: [SourceRecord] = try SourceRecord
                .filter(SourceRecord.Columns.userID == userID)
                .fetchAll(database)
            let sourceCount: Int = sourceRecords.filter { record in
                return record.id.hasPrefix("built-in.") == false
            }.count
            let favoriteItemCount: Int = try FavoriteItemRecord
                .filter(FavoriteItemRecord.Columns.userID == userID)
                .fetchCount(database)
            return CloudAccountPartitionSummary(
                sourceCount: sourceCount,
                favoriteItemCount: favoriteItemCount
            )
        }
    }

    func associatedUserID(for cloudScope: CloudAccountScope) throws -> UUID? {
        guard cloudScope.isCloud else {
            throw CloudAccountPartitionError.invalidCloudScope
        }
        return try self.database.queue.read { database in
            guard let record: CloudAppUserAssociationAttestationRecord =
                try CloudAppUserAssociationAttestationRecord.fetchOne(
                    database,
                    key: cloudScope.rawValue
                ) else {
                return nil
            }
            return UUID(uuidString: record.userID)
        }
    }

    func attestAssociation(
        cloudScope: CloudAccountScope,
        userID: UUID
    ) throws {
        guard cloudScope.isCloud else {
            throw CloudAccountPartitionError.invalidCloudScope
        }
        try self.database.queue.write { database in
            let record: CloudAppUserAssociationAttestationRecord =
                CloudAppUserAssociationAttestationRecord(
                    accountScope: cloudScope.rawValue,
                    userID: userID.uuidString,
                    associatedAt: Date()
                )
            try record.save(database)
        }
    }

    func preparation(
        for cloudScope: CloudAccountScope
    ) throws -> CloudAccountPartitionPreparation? {
        guard cloudScope.isCloud else {
            throw CloudAccountPartitionError.invalidCloudScope
        }

        return try self.database.queue.read { database in
            guard let record: CloudAccountPartitionPreparationRecord =
                try CloudAccountPartitionPreparationRecord.fetchOne(
                    database,
                    key: cloudScope.rawValue
                ),
                record.userID == self.currentUserID else {
                return nil
            }
            return record.preparation
        }
    }

    func markInitialSyncCompleted(
        for cloudScope: CloudAccountScope,
        at completedAt: Date
    ) throws {
        guard cloudScope.isCloud else {
            throw CloudAccountPartitionError.invalidCloudScope
        }

        try self.database.queue.write { database in
            guard var record: CloudAccountPartitionPreparationRecord = try
                CloudAccountPartitionPreparationRecord.fetchOne(
                    database,
                    key: cloudScope.rawValue
                ) else {
                return
            }
            guard record.userID == self.currentUserID else {
                return
            }
            guard record.initialSyncCompletedAt == nil else {
                return
            }
            record.initialSyncCompletedAt = completedAt
            try record.update(database)
        }
    }

    func prepareCloudScope(
        _ cloudScope: CloudAccountScope,
        decision: CloudAccountLocalDataDecision
    ) throws -> CloudAccountPartitionMergeResult {
        guard cloudScope.isCloud else {
            throw CloudAccountPartitionError.invalidCloudScope
        }
        let userID: String = self.currentUserID

        return try self.database.queue.write { database in
            if let existingRecord: CloudAccountPartitionPreparationRecord = try
                CloudAccountPartitionPreparationRecord.fetchOne(
                    database,
                    key: cloudScope.rawValue
                ),
                existingRecord.userID == userID {
                guard existingRecord.decision == decision else {
                    throw CloudAccountPartitionError.alreadyPrepared(
                        existingDecision: existingRecord.decision
                    )
                }
                return CloudAccountPartitionMergeResult(
                    copiedSourceCount: 0,
                    copiedFavoriteItemCount: 0,
                    skippedCount: 0,
                    wasAlreadyPrepared: true
                )
            }
            _ = try CloudAccountPartitionPreparationRecord
                .filter(
                    CloudAccountPartitionPreparationRecord.Columns.accountScope ==
                        cloudScope.rawValue
                )
                .deleteAll(database)

            let result: CloudAccountPartitionMergeResult

            switch decision {
            case .useCloudDataOnly:
                try Self.removeLocalCloudContent(
                    userID: userID,
                    in: database
                )
                result = CloudAccountPartitionMergeResult(
                    copiedSourceCount: 0,
                    copiedFavoriteItemCount: 0,
                    skippedCount: 0,
                    wasAlreadyPrepared: false
                )

            case .mergeLocalData:
                let sourceCount: Int = try Self.enqueueSources(
                    userID: userID,
                    accountScope: cloudScope,
                    in: database
                )
                let favoriteCount: Int = try Self.enqueueFavoriteItems(
                    userID: userID,
                    accountScope: cloudScope,
                    in: database
                )
                result = CloudAccountPartitionMergeResult(
                    copiedSourceCount: sourceCount,
                    copiedFavoriteItemCount: favoriteCount,
                    skippedCount: 0,
                    wasAlreadyPrepared: false
                )
            }

            try CloudAccountPartitionPreparationRecord(
                accountScope: cloudScope.rawValue,
                userID: userID,
                decision: decision,
                preparedAt: Date(),
                initialSyncCompletedAt: nil
            ).insert(database)
            return result
        }
    }

    private static func enqueueSources(
        userID: String,
        accountScope: CloudAccountScope,
        in database: Database
    ) throws -> Int {
        let records: [SourceRecord] = try SourceRecord
            .filter(SourceRecord.Columns.userID == userID)
            .fetchAll(database)
        var count: Int = 0
        for record: SourceRecord in records {
            guard record.id.hasPrefix("built-in.") == false else {
                continue
            }
            try SyncQueueRecord.enqueue(
                accountScope: accountScope,
                entityType: .source,
                entityID: record.id,
                operation: record.deletedAt == nil ? .upsert : .delete,
                updatedAt: record.lastChangedAt,
                in: database
            )
            count += 1
        }
        return count
    }

    private static func enqueueFavoriteItems(
        userID: String,
        accountScope: CloudAccountScope,
        in database: Database
    ) throws -> Int {
        let records: [FavoriteItemRecord] = try FavoriteItemRecord
            .filter(FavoriteItemRecord.Columns.userID == userID)
            .fetchAll(database)
        var count: Int = 0
        for record: FavoriteItemRecord in records {
            try SyncQueueRecord.enqueue(
                accountScope: accountScope,
                entityType: .favoriteItem,
                entityID: FavoriteItemIdentity(
                    sourceID: record.sourceID,
                    itemID: record.itemID
                ).syncEntityID,
                operation: record.deletedAt == nil ? .upsert : .delete,
                updatedAt: record.lastChangedAt,
                in: database
            )
            count += 1
        }
        return count
    }

    private static func removeLocalCloudContent(
        userID: String,
        in database: Database
    ) throws {
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
        try database.execute(
            sql: """
            UPDATE \(UserLibraryStateRecord.databaseTableName)
            SET selectedSourceID = NULL,
                listContextJSON = NULL,
                lastRefreshAt = NULL,
                updatedAt = ?
            WHERE userID = ?
            """,
            arguments: [Date(), userID]
        )
    }

    private var currentUserID: String {
        return self.activeAppUser?.currentUserID.uuidString ?? AppUser.localDefaultID
    }
}

struct CloudAccountPartitionPreparationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "cloud_account_partition_preparations"

    enum Columns {
        static let accountScope: Column = Column("accountScope")
    }

    var accountScope: String
    var userID: String
    var decision: CloudAccountLocalDataDecision
    var preparedAt: Date
    var initialSyncCompletedAt: Date?

    var preparation: CloudAccountPartitionPreparation {
        return CloudAccountPartitionPreparation(
            decision: self.decision,
            preparedAt: self.preparedAt,
            initialSyncCompletedAt: self.initialSyncCompletedAt
        )
    }
}

struct CloudAppUserAssociationAttestationRecord:
    Codable,
    FetchableRecord,
    PersistableRecord {
    static let databaseTableName: String =
        "cloud_app_user_association_attestations"

    var accountScope: String
    var userID: String
    var associatedAt: Date
}
