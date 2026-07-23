import Foundation
import GRDB

// 中文注释：GRDBSourceRepository 通过 SQLite 保存、读取和删除 Source。

/// 中文注释：Source 删除采用应用级级联规则，避免留下无法恢复的 history/library state。
final class GRDBSourceRepository: SourceRepository {
    private let database: AppDatabase
    private let accountScopeProvider: any ActiveAccountScopeProviding
    private let changeNotifier: (any CloudSyncChangeNotifying)?

    init(
        database: AppDatabase,
        accountScopeProvider: any ActiveAccountScopeProviding = ActiveAccountScopeStore(),
        changeNotifier: (any CloudSyncChangeNotifying)? = nil
    ) {
        self.database = database
        self.accountScopeProvider = accountScopeProvider
        self.changeNotifier = changeNotifier
    }

    func fetchSources() throws -> [Source] {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        return try self.database.queue.read { database in
            var records: [SourceRecord] = try SourceRecord
                .filter(SourceRecord.Columns.userID == accountScope.rawValue)
                .filter(SourceRecord.Columns.deletedAt == nil)
                .order(SourceRecord.Columns.updatedAt.desc)
                .fetchAll(database)

            if accountScope.isCloud {
                let builtInRecords: [SourceRecord] = try SourceRecord
                    .filter(SourceRecord.Columns.userID == CloudAccountScope.localDefault.rawValue)
                    .filter(SourceRecord.Columns.deletedAt == nil)
                    .fetchAll(database)
                    .filter { record in
                        return record.id.hasPrefix("built-in.")
                    }
                let currentIDs: Set<String> = Set(records.map(\.id))
                records.append(contentsOf: builtInRecords.filter { record in
                    return currentIDs.contains(record.id) == false
                })
                records.sort { lhs, rhs in
                    return lhs.updatedAt > rhs.updatedAt
                }
            }

            return try records.map { record in
                return try record.domainModel()
            }
        }
    }

    func saveSource(_ source: Source) throws {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        try self.database.queue.write { database in
            try AppUserRecord.insertLocalDefaultUser(in: database)
            try AppUserRecord.insertUser(id: accountScope.rawValue, in: database)

            let existingRecord: SourceRecord? = try SourceRecord.fetchOne(
                database,
                key: ["userID": accountScope.rawValue, "id": source.id]
            )
            let existingSourceIsActive: Bool = existingRecord.map { record in
                return record.deletedAt == nil
            } ?? false
            if SourceSlotPolicy.consumesNewSlot(
                source: source,
                existingSourceIsActive: existingSourceIsActive
            ) {
                let entitlementUser: AppUserRecord? = try AppUserRecord.fetchOne(
                    database,
                    key: AppUser.localDefaultID
                )
                let siteSlotLimit: Int = SourceSlotPolicy.effectiveLimit(
                    storedLimit: entitlementUser?.siteSlotLimit ?? SourceSlotPolicy.includedSiteSlotCount
                )
                let occupiedSiteSlotCount: Int = try Int.fetchOne(
                    database,
                    sql: """
                    SELECT COUNT(*)
                    FROM \(SourceRecord.databaseTableName)
                    WHERE userID = ?
                      AND deletedAt IS NULL
                      AND id NOT LIKE 'built-in.%'
                    """,
                    arguments: [accountScope.rawValue]
                ) ?? 0

                guard occupiedSiteSlotCount < siteSlotLimit else {
                    throw SourceRepositoryError.siteSlotLimitReached(limit: siteSlotLimit)
                }
            }

            var record: SourceRecord = try SourceRecord(source: source)
            record.userID = accountScope.rawValue
            try record.save(database)

            if source.isBuiltIn == false {
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .source,
                    entityID: source.id,
                    operation: .upsert,
                    updatedAt: source.updatedAt,
                    in: database
                )
            }
        }
        if source.isBuiltIn == false {
            self.changeNotifier?.notifyLocalChange()
        }
    }

    func deleteSource(id: String) throws {
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        try self.database.queue.write { database in
            let now: Date = Date()
            try Self.clearSourceSelection(
                accountScope: accountScope,
                sourceID: id,
                in: database
            )

            if var record: SourceRecord = try SourceRecord.fetchOne(
                database,
                key: ["userID": accountScope.rawValue, "id": id]
            ) {
                record.updatedAt = now
                record.deletedAt = now
                try record.save(database)
            }

            if id.hasPrefix("built-in.") == false {
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .source,
                    entityID: id,
                    operation: .delete,
                    updatedAt: now,
                    in: database
                )
            }
        }
        if id.hasPrefix("built-in.") == false {
            self.changeNotifier?.notifyLocalChange()
        }
    }

    /// 中文注释：Source 只拥有 Library 当前选择状态；历史和收藏都依靠快照独立于来源生命周期。
    private static func clearSourceSelection(
        accountScope: CloudAccountScope,
        sourceID: String,
        in database: Database
    ) throws {
        try database.execute(
            sql: """
            UPDATE \(UserLibraryStateRecord.databaseTableName)
            SET selectedSourceID = NULL,
                listContextJSON = NULL,
                lastRefreshAt = NULL,
                updatedAt = ?
            WHERE userID = ? AND selectedSourceID = ?
            """,
            arguments: [
                Date(),
                accountScope.rawValue,
                sourceID
            ]
        )
    }
}
