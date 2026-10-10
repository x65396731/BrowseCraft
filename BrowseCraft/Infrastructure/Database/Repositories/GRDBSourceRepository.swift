import BrowseCraftDomain
import Foundation
import GRDB

// 中文注释：GRDBSourceRepository 通过 SQLite 保存、读取和删除 Source。

/// 中文注释：Source 删除是应用级的连带删除（`BCA-DB-004`、`BCA-DB-005`）：同一写事务里清空指向它的库当前选择、
/// 删掉该用户该来源的三张历史表记录、给它的收藏写删除标记并逐条入队，再重建收藏汇总；不依赖外键级联。
/// 被删内容作为留底交回，撤销时由 `restoreDeletedSource` 原样写回。
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
        try self.saveCatalogSources([source], fingerprintsBySourceID: [:])
    }

    /// 中文注释：一个写事务里逐条保存；指纹表里有的来源把 `catalogRuleFingerprint` 一起写上（复审 B-4）。
    func saveCatalogSources(_ sources: [Source], fingerprintsBySourceID: [String: String]) throws {
        guard sources.isEmpty == false else {
            return
        }
        let userID: String = self.currentUserID
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        try self.database.queue.write { database in
            try AppUserRecord.insertUser(id: userID, in: database)
            for source: Source in sources {
                try Self.save(
                    source,
                    catalogRuleFingerprint: fingerprintsBySourceID[source.id],
                    userID: userID,
                    accountScope: accountScope,
                    in: database
                )
            }
        }
        if sources.contains(where: { $0.isBuiltIn == false }) {
            self.changeNotifier?.notifyLocalChange()
        }
    }

    func catalogRuleFingerprints() throws -> [String: String] {
        let userID: String = self.currentUserID
        return try self.database.queue.read { database in
            let rows: [Row] = try Row.fetchAll(
                database,
                sql: """
                SELECT id, catalogRuleFingerprint
                FROM \(SourceRecord.databaseTableName)
                WHERE userID = ? AND deletedAt IS NULL AND catalogRuleFingerprint IS NOT NULL
                """,
                arguments: [userID]
            )
            var fingerprints: [String: String] = [:]
            for row: Row in rows {
                fingerprints[row["id"]] = row["catalogRuleFingerprint"]
            }
            return fingerprints
        }
    }

    func stampCatalogRuleFingerprints(_ fingerprintsBySourceID: [String: String]) throws {
        guard fingerprintsBySourceID.isEmpty == false else {
            return
        }
        let userID: String = self.currentUserID
        try self.database.queue.write { database in
            for (sourceID, fingerprint) in fingerprintsBySourceID {
                try database.execute(
                    sql: """
                    UPDATE \(SourceRecord.databaseTableName)
                    SET catalogRuleFingerprint = ?
                    WHERE userID = ? AND id = ?
                    """,
                    arguments: [fingerprint, userID, sourceID]
                )
            }
        }
    }

    private static func save(
        _ source: Source,
        catalogRuleFingerprint: String?,
        userID: String,
        accountScope: CloudAccountScope,
        in database: Database
    ) throws {
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
        record.catalogRuleFingerprint = catalogRuleFingerprint
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

    /// 中文注释：用户删除来源（`BCA-DB-005`）。这里**不**发本地变更通知：删除后有一段撤销窗口，
    /// 通知由调用方在窗口结束时经 `notifyLocalChanges()` 补发，撤销了就不发——删除在窗口里一般不会被上传。
    @discardableResult
    func deleteSource(id: String) throws -> SourceDeletionReceipt? {
        let userID: String = self.currentUserID
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        let isBuiltIn: Bool = id.hasPrefix("built-in.")
        return try self.database.queue.write { database -> SourceDeletionReceipt? in
            let now: Date = Date()
            let existingRecord: SourceRecord? = try SourceRecord.fetchOne(
                database,
                key: ["userID": userID, "id": id]
            )
            // 中文注释：留底只给在册且能解出来的来源；解不出配置的来源照样删，只是不能撤销。
            let liveSource: Source? = existingRecord.flatMap { (record: SourceRecord) -> Source? in
                guard record.deletedAt == nil else {
                    return nil
                }
                return try? record.domainModel()
            }
            let librarySelection: UserLibraryState? = try UserLibraryStateRecord
                .filter(UserLibraryStateRecord.Columns.userID == userID)
                .fetchOne(database)
                .flatMap { (record: UserLibraryStateRecord) -> UserLibraryState? in
                    return record.selectedSourceID == id ? record.domainModel() : nil
                }

            try Self.clearSourceSelection(
                userID: userID,
                sourceID: id,
                in: database
            )

            if var record: SourceRecord = existingRecord {
                record.updatedAt = now
                record.deletedAt = now
                try record.save(database)
            }

            if isBuiltIn == false {
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .source,
                    entityID: id,
                    operation: .delete,
                    updatedAt: now,
                    in: database
                )
            }

            let histories: DeletedSourceHistories = try Self.deleteHistories(
                userID: userID,
                sourceID: id,
                in: database
            )
            let favoriteItems: [FavoriteContentItem] = try Self.markFavoritesDeleted(
                userID: userID,
                sourceID: id,
                accountScope: accountScope,
                now: now,
                in: database
            )

            guard let source: Source = liveSource else {
                return nil
            }
            return SourceDeletionReceipt(
                source: source,
                librarySelection: librarySelection,
                comicHistories: histories.comic,
                videoHistories: histories.video,
                bookHistories: histories.book,
                favoriteItems: favoriteItems,
                enqueuedSyncChanges: isBuiltIn == false || favoriteItems.isEmpty == false
            )
        }
    }

    /// 中文注释：撤销删除：来源恢复为在册（更新时间取当前时间，启用状态照旧），三张历史表记录与收藏原样写回
    /// （含原访问时间、原收藏时间），来源（非内置）与每条收藏以当前时间重新入队为更新——
    /// `SyncQueueRecord.enqueue` 让较新的更新覆盖尚未上传的删除。删除前它是当前来源的，库状态也一并写回。
    func restoreDeletedSource(_ receipt: SourceDeletionReceipt) throws {
        let userID: String = self.currentUserID
        let accountScope: CloudAccountScope = self.accountScopeProvider.currentScope
        let isBuiltIn: Bool = receipt.source.isBuiltIn
        try self.database.queue.write { database in
            let now: Date = Date()
            try AppUserRecord.insertUser(id: userID, in: database)

            var record: SourceRecord = try SourceRecord(source: receipt.source)
            record.userID = userID
            record.deletedAt = nil
            record.updatedAt = now
            try record.save(database)
            if isBuiltIn == false {
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .source,
                    entityID: receipt.source.id,
                    operation: .upsert,
                    updatedAt: now,
                    in: database
                )
            }

            // 中文注释：撤销窗口里用户可能又看过同一章 / 同一部，按唯一键覆盖而不是报错。
            for history: ComicChapterHistory in receipt.comicHistories {
                var historyRecord: ComicChapterHistoryRecord = ComicChapterHistoryRecord(history: history)
                historyRecord.userID = userID
                try historyRecord.insert(database, onConflict: .replace)
            }
            for history: VideoWatchHistory in receipt.videoHistories {
                var historyRecord: VideoWatchHistoryRecord = VideoWatchHistoryRecord(history: history)
                historyRecord.userID = userID
                try historyRecord.insert(database, onConflict: .replace)
            }
            for history: BookReadingHistory in receipt.bookHistories {
                var historyRecord: BookReadingHistoryRecord = BookReadingHistoryRecord(history: history)
                historyRecord.userID = userID
                try historyRecord.insert(database, onConflict: .replace)
            }

            for item: FavoriteContentItem in receipt.favoriteItems {
                var itemRecord: FavoriteItemRecord = try FavoriteItemRecord(
                    userID: userID,
                    item: item,
                    updatedAt: now,
                    deletedAt: nil
                )
                if let existingItemRecord: FavoriteItemRecord = try FavoriteItemRecord.fetchOne(
                    database,
                    key: ["userID": userID, "sourceID": item.sourceID, "itemID": item.id]
                ) {
                    itemRecord.createdAt = existingItemRecord.createdAt
                }
                try itemRecord.save(database)
                try SyncQueueRecord.enqueue(
                    accountScope: accountScope,
                    entityType: .favoriteItem,
                    entityID: item.identity.syncEntityID,
                    operation: .upsert,
                    updatedAt: now,
                    in: database
                )
            }
            if receipt.favoriteItems.isEmpty == false {
                try FavoriteAggregateBuilder.rebuild(userID: userID, in: database)
            }

            if var librarySelection: UserLibraryState = receipt.librarySelection {
                librarySelection.userID = userID
                librarySelection.updatedAt = now
                var stateRecord: UserLibraryStateRecord = try UserLibraryStateRecord(state: librarySelection)
                try stateRecord.save(database)
            }
        }
        if isBuiltIn == false || receipt.favoriteItems.isEmpty == false {
            self.changeNotifier?.notifyLocalChange()
        }
    }

    func notifyLocalChanges() {
        self.changeNotifier?.notifyLocalChange()
    }

    /// 中文注释：删除来源（本机用户删除或 iCloud 应用远端删除）时删掉该用户该来源在三张历史表里的全部记录
    /// （`BCA-DB-005`），交回被删记录供撤销。三张表的唯一键 / 主键都以用户与来源开头，不需要额外索引。
    /// 站点书的续读位置与书签没有来源列，不动。
    @discardableResult
    static func deleteHistories(
        userID: String,
        sourceID: String,
        in database: Database
    ) throws -> DeletedSourceHistories {
        let comicRecords: [ComicChapterHistoryRecord] = try ComicChapterHistoryRecord
            .filter(ComicChapterHistoryRecord.Columns.userID == userID)
            .filter(ComicChapterHistoryRecord.Columns.sourceID == sourceID)
            .fetchAll(database)
        let videoRecords: [VideoWatchHistoryRecord] = try VideoWatchHistoryRecord
            .filter(VideoWatchHistoryRecord.Columns.userID == userID)
            .filter(VideoWatchHistoryRecord.Columns.sourceID == sourceID)
            .fetchAll(database)
        let bookRecords: [BookReadingHistoryRecord] = try BookReadingHistoryRecord
            .filter(BookReadingHistoryRecord.Columns.userID == userID)
            .filter(BookReadingHistoryRecord.Columns.sourceID == sourceID)
            .fetchAll(database)

        for tableName: String in [
            ComicChapterHistoryRecord.databaseTableName,
            VideoWatchHistoryRecord.databaseTableName,
            BookReadingHistoryRecord.databaseTableName
        ] {
            try database.execute(
                sql: "DELETE FROM \(tableName) WHERE userID = ? AND sourceID = ?",
                arguments: [userID, sourceID]
            )
        }

        return DeletedSourceHistories(
            comic: comicRecords.map { record in record.domainModel() },
            video: videoRecords.map { record in record.domainModel() },
            book: bookRecords.map { record in record.domainModel() }
        )
    }

    /// 中文注释：给该用户该来源每条在册收藏写删除标记、按 `FavoriteItemIdentity` 的同步实体 ID 逐条入队，
    /// 最后重建一次收藏汇总（与取消收藏同一写法）。内置来源的收藏也要入队，否则其他设备会把收藏同步回来。
    private static func markFavoritesDeleted(
        userID: String,
        sourceID: String,
        accountScope: CloudAccountScope,
        now: Date,
        in database: Database
    ) throws -> [FavoriteContentItem] {
        let liveRecords: [FavoriteItemRecord] = try FavoriteItemRecord
            .filter(FavoriteItemRecord.Columns.userID == userID)
            .filter(FavoriteItemRecord.Columns.sourceID == sourceID)
            .filter(FavoriteItemRecord.Columns.deletedAt == nil)
            .fetchAll(database)
        guard liveRecords.isEmpty == false else {
            return []
        }

        var deletedItems: [FavoriteContentItem] = []
        for var record: FavoriteItemRecord in liveRecords {
            if let item: FavoriteContentItem = record.favoriteItem() {
                deletedItems.append(item)
            }
            record.updatedAt = now
            record.deletedAt = now
            try record.save(database)
            try SyncQueueRecord.enqueue(
                accountScope: accountScope,
                entityType: .favoriteItem,
                entityID: FavoriteItemIdentity(sourceID: record.sourceID, itemID: record.itemID).syncEntityID,
                operation: .delete,
                updatedAt: now,
                in: database
            )
        }
        try FavoriteAggregateBuilder.rebuild(userID: userID, in: database)
        return deletedItems
    }

    /// 中文注释：删除来源时，库的当前选择正好是它就清空（`BCA-DB-004`）；历史与收藏由 `deleteHistories` /
    /// `markFavoritesDeleted` 在同一事务里连带删除（`BCA-DB-005`），不再靠快照独立于来源生命周期。
    static func clearSourceSelection(
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

/// 中文注释：一次来源删除从三张历史表里删掉的记录，按表分开交回。
struct DeletedSourceHistories: Sendable {
    let comic: [ComicChapterHistory]
    let video: [VideoWatchHistory]
    let book: [BookReadingHistory]
}
