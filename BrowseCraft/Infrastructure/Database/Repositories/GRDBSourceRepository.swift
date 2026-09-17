import BrowseCraftDomain
import Foundation
import GRDB

// 中文注释：GRDBSourceRepository 通过 SQLite 保存、读取和删除 Source。

/// 中文注释：Source 删除采用应用级级联规则，避免留下无法恢复的 history/library state。
final class GRDBSourceRepository: SourceRepository {
    private let database: AppDatabase
    private let activeAppUser: (any ActiveAppUserProviding)?
    private let accountScopeProvider: any ActiveAccountScopeProviding
    private let changeNotifier: (any CloudSyncChangeNotifying)?

    init(
        database: AppDatabase,
        activeAppUser: (any ActiveAppUserProviding)? = nil,
        accountScopeProvider: any ActiveAccountScopeProviding = ActiveAccountScopeStore(),
        changeNotifier: (any CloudSyncChangeNotifying)? = nil
    ) {
        self.database = database
        self.activeAppUser = activeAppUser
        self.accountScopeProvider = accountScopeProvider
        self.changeNotifier = changeNotifier
    }

    func fetchSources() throws -> [Source] {
        let userID: String = self.currentUserID
        return try self.database.queue.read { database in
            return try Self.fetchDomainSources(userID: userID, in: database)
        }
    }

    private static func fetchDomainSources(userID: String, in database: Database) throws -> [Source] {
        let records: [SourceRecord] = try SourceRecord
            .filter(SourceRecord.Columns.userID == userID)
            .filter(SourceRecord.Columns.deletedAt == nil)
            .order(SourceRecord.Columns.updatedAt.desc)
            .fetchAll(database)

        return try records.map { record in
            return try record.domainModel()
        }
    }

    /// 中文注释：槽位归置用的候选查询——非内置、未删除，按启用、更新时间、id 排序；读判断与写归置共用同一份 SQL。
    private static func fetchSlotCandidateRecords(userID: String, in database: Database) throws -> [SourceRecord] {
        return try SourceRecord.fetchAll(
            database,
            sql: """
            SELECT *
            FROM \(SourceRecord.databaseTableName)
            WHERE userID = ?
              AND deletedAt IS NULL
              AND id NOT LIKE 'built-in.%'
            ORDER BY enabled DESC, updatedAt DESC, id ASC
            """,
            arguments: [userID]
        )
    }

    private static func siteSlotLimit(userID: String, in database: Database) throws -> Int {
        let entitlementUser: AppUserRecord? = try AppUserRecord.fetchOne(database, key: userID)
        return SourceSlotPolicy.effectiveLimit(
            storedLimit: entitlementUser?.siteSlotLimit ?? SourceSlotPolicy.includedSiteSlotCount
        )
    }

    private enum ReconcileReadOutcome {
        /// 已按槽位规则就位，且用户行存在：直接返回同一次读事务里解出的来源。
        case settled([Source])
        /// 有来源的启用状态需要翻转，或用户行尚不存在：进入写事务。
        case needsWrite
    }

    func saveSource(_ source: Source) throws {
        let userID: String = self.currentUserID
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: userID, in: database)

            let existingRecord: SourceRecord? = try SourceRecord.fetchOne(
                database,
                key: ["userID": userID, "id": source.id]
            )
            let existingSourceConsumesSlot: Bool = existingRecord.map { record in
                return record.deletedAt == nil
                    && record.id.hasPrefix("built-in.") == false
                    && record.enabled
            } ?? false
            if SourceSlotPolicy.consumesNewSlot(
                source: source,
                existingSourceConsumesSlot: existingSourceConsumesSlot
            ) {
                let entitlementUser: AppUserRecord? = try AppUserRecord.fetchOne(
                    database,
                    key: userID
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
                      AND enabled = 1
                    """,
                    arguments: [userID]
                ) ?? 0

                guard occupiedSiteSlotCount < siteSlotLimit else {
                    throw SourceRepositoryError.siteSlotLimitReached(limit: siteSlotLimit)
                }
            }

            var record: SourceRecord = try SourceRecord(source: source)
            record.userID = userID
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

    func reconcileSourceSlotAssignments() throws -> [Source] {
        let userID: String = self.currentUserID
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        var changedSourceCount: Int = 0

        // 中文注释：每次进列表都会调用。先在读事务里判断是否真的需要归置；多数情况下没有任何来源
        // 需要翻转启用状态，此时直接返回这次读出的来源，不开写事务（写事务会与 CloudSync 写者争 WAL 写锁），
        // 也不再第二次读出并解码全部来源。用户行不存在时仍走写路径，保持「归置后用户行必定存在」的不变量。
        let readOutcome: ReconcileReadOutcome = try self.database.queue.read { database in
            guard try AppUserRecord.exists(database, key: userID) else {
                return .needsWrite
            }
            let siteSlotLimit: Int = try Self.siteSlotLimit(userID: userID, in: database)
            let records: [SourceRecord] = try Self.fetchSlotCandidateRecords(userID: userID, in: database)
            let activeSourceIDs: Set<String> = Set(records.prefix(siteSlotLimit).map(\.id))
            let needsChange: Bool = records.contains { record in
                return record.enabled != activeSourceIDs.contains(record.id)
            }
            guard needsChange == false else {
                return .needsWrite
            }
            return .settled(try Self.fetchDomainSources(userID: userID, in: database))
        }
        if case .settled(let sources) = readOutcome {
            return sources
        }

        try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: userID, in: database)
            let siteSlotLimit: Int = try Self.siteSlotLimit(userID: userID, in: database)
            let records: [SourceRecord] = try Self.fetchSlotCandidateRecords(userID: userID, in: database)
            let activeSourceIDs: Set<String> = Set(
                records.prefix(siteSlotLimit).map(\.id)
            )
            let now: Date = Date()

            for var record: SourceRecord in records {
                let shouldBeEnabled: Bool = activeSourceIDs.contains(record.id)
                guard record.enabled != shouldBeEnabled else {
                    continue
                }

                record.enabled = shouldBeEnabled
                record.updatedAt = now
                try record.save(database)
                if shouldBeEnabled == false {
                    try Self.clearSourceSelection(
                        userID: userID,
                        sourceID: record.id,
                        in: database
                    )
                }
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .source,
                    entityID: record.id,
                    operation: .upsert,
                    updatedAt: record.updatedAt,
                    in: database
                )
                changedSourceCount += 1
            }
        }

        if changedSourceCount > 0 {
            self.changeNotifier?.notifyLocalChange()
        }
        return try self.fetchSources()
    }

    func activateSource(
        id: String,
        replacingSourceID: String?
    ) throws -> [Source] {
        let userID: String = self.currentUserID
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        var changedSourceCount: Int = 0

        try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: userID, in: database)
            guard var target: SourceRecord = try SourceRecord.fetchOne(
                database,
                key: ["userID": userID, "id": id]
            ),
                  target.deletedAt == nil,
                  target.id.hasPrefix("built-in.") == false else {
                throw SourceRepositoryError.invalidSourceSlotReplacement
            }
            guard target.enabled == false else {
                return
            }

            let entitlementUser: AppUserRecord? = try AppUserRecord.fetchOne(
                database,
                key: userID
            )
            let siteSlotLimit: Int = SourceSlotPolicy.effectiveLimit(
                storedLimit: entitlementUser?.siteSlotLimit ??
                    SourceSlotPolicy.includedSiteSlotCount
            )
            let occupiedSiteSlotCount: Int = try Int.fetchOne(
                database,
                sql: """
                SELECT COUNT(*)
                FROM \(SourceRecord.databaseTableName)
                WHERE userID = ?
                  AND deletedAt IS NULL
                  AND id NOT LIKE 'built-in.%'
                  AND enabled = 1
                """,
                arguments: [userID]
            ) ?? 0
            let now: Date = Date()
            var changedRecords: [SourceRecord] = []

            if occupiedSiteSlotCount >= siteSlotLimit {
                guard let replacingSourceID,
                      replacingSourceID != id,
                      var replacement: SourceRecord = try SourceRecord.fetchOne(
                        database,
                        key: ["userID": userID, "id": replacingSourceID]
                      ),
                      replacement.deletedAt == nil,
                      replacement.id.hasPrefix("built-in.") == false,
                      replacement.enabled else {
                    throw SourceRepositoryError.invalidSourceSlotReplacement
                }
                replacement.enabled = false
                replacement.updatedAt = now
                try Self.clearSourceSelection(
                    userID: userID,
                    sourceID: replacement.id,
                    in: database
                )
                changedRecords.append(replacement)
            }

            target.enabled = true
            target.updatedAt = now
            changedRecords.append(target)

            for var record: SourceRecord in changedRecords {
                try record.save(database)
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .source,
                    entityID: record.id,
                    operation: .upsert,
                    updatedAt: record.updatedAt,
                    in: database
                )
                changedSourceCount += 1
            }
        }

        if changedSourceCount > 0 {
            self.changeNotifier?.notifyLocalChange()
        }
        return try self.fetchSources()
    }

    func deleteSource(id: String) throws {
        let userID: String = self.currentUserID
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        try self.database.queue.write { database in
            let now: Date = Date()
            try Self.clearSourceSelection(
                userID: userID,
                sourceID: id,
                in: database
            )

            if var record: SourceRecord = try SourceRecord.fetchOne(
                database,
                key: ["userID": userID, "id": id]
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
        userID: String,
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
                userID,
                sourceID
            ]
        )
    }

    /// 中文注释：nil 仅保留给既存隔离测试；App Composition Root 必须注入稳定业务用户。
    private var currentUserID: String {
        return self.activeAppUser?.currentUserID.uuidString ?? AppUser.localDefaultID
    }
}
